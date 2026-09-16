-- LinkedIn writing quality, last seven days (KAN-306 F1, 2026-09-16)
--
-- One query, fixed columns, so the operator can paste the result straight back
-- into the ticket. Read-only: it writes nothing and takes no locks worth
-- noticing.
--
-- One row per campaign per invitation mode, plus an ALL rollup per campaign.
-- Gates G20 to G25 read these columns directly:
--
--   G20  voice_none  = 0 for any rep with an approved card
--   G21  lint_*      = 0 for label_echo, stat_hook, content_compliment, location_mention
--   G22  mode        never 'unset' (every invitation records the rung it used)
--   G23  step1_no_history = 0 for threads started after the deploy
--   G25  over_cap    = 0
--
-- The two rates are the point of the whole exercise:
--
--   edit_rate    how often a human had to rewrite us before sending. Compares
--                what was SENT (thread_plan.steps[0].sent_text, written by the
--                dispatch at the one confirmed-send site) against the draft as
--                the model wrote it (metadata.draft_original, stamped at task
--                creation). tasks.body and pre_generated_copy both become
--                whatever was approved, so neither can answer this.
--   accept_rate  share of those invitations whose journey reached connected.
--
-- Usage:  psql "$STAGE_URL" -f operations/sql/linkedin_writing_weekly.sql

WITH invitations AS (
    SELECT
        t.id,
        t.campaign_id,
        c.name                                            AS campaign_name,
        COALESCE(NULLIF(t.metadata->>'invite_mode', ''), 'unset')  AS mode,
        COALESCE(NULLIF(t.metadata->>'voice_src', ''), 'none')     AS voice_src,
        t.metadata->>'draft_original'                     AS draft_original,
        t.metadata->'lint'                                AS lint,
        t.status,
        -- What the person actually read. NULL until the invitation is sent.
        cc.state_metadata->'thread_plan'->'steps'->0->>'sent_text'  AS sent_text,
        cc.relation_state,
        length(COALESCE(t.metadata->>'draft_original', ''))         AS draft_chars,
        -- Counted per invitation here so the outer query can just sum them.
        (SELECT count(*) FROM jsonb_array_elements(
             CASE WHEN jsonb_typeof(t.metadata->'lint') = 'array'
                  THEN t.metadata->'lint' ELSE '[]'::jsonb END) e
         WHERE e->>'code' = 'label_echo')          AS n_label_echo,
        (SELECT count(*) FROM jsonb_array_elements(
             CASE WHEN jsonb_typeof(t.metadata->'lint') = 'array'
                  THEN t.metadata->'lint' ELSE '[]'::jsonb END) e
         WHERE e->>'code' = 'stat_hook')           AS n_stat_hook,
        (SELECT count(*) FROM jsonb_array_elements(
             CASE WHEN jsonb_typeof(t.metadata->'lint') = 'array'
                  THEN t.metadata->'lint' ELSE '[]'::jsonb END) e
         WHERE e->>'code' = 'content_compliment')  AS n_content_compliment,
        (SELECT count(*) FROM jsonb_array_elements(
             CASE WHEN jsonb_typeof(t.metadata->'lint') = 'array'
                  THEN t.metadata->'lint' ELSE '[]'::jsonb END) e
         WHERE e->>'code' = 'location_mention')    AS n_location_mention,
        (SELECT count(*) FROM jsonb_array_elements(
             CASE WHEN jsonb_typeof(t.metadata->'lint') = 'array'
                  THEN t.metadata->'lint' ELSE '[]'::jsonb END) e
         WHERE e->>'code' = 'campaign_sameness')   AS n_campaign_sameness,
        (SELECT count(*) FROM jsonb_array_elements(
             CASE WHEN jsonb_typeof(t.metadata->'lint') = 'array'
                  THEN t.metadata->'lint' ELSE '[]'::jsonb END) e
         WHERE e->>'code' = 'date_in_note')        AS n_date_in_note
    FROM tasks t
    JOIN campaigns c
      ON c.id = t.campaign_id
    LEFT JOIN campaign_contacts cc
      ON cc.id = NULLIF(t.metadata->>'campaign_contact_id', '')::uuid
    WHERE t.task_type = 'review_draft'
      AND t.metadata->>'channel' = 'linkedin'
      AND t.metadata->>'linkedin_action_type' = 'invitation'
      AND t.created_at >= now() - interval '7 days'
),
rows_with_rollup AS (
    SELECT campaign_name, mode, voice_src, draft_original, sent_text, relation_state, draft_chars,
           n_label_echo, n_stat_hook, n_content_compliment, n_location_mention,
           n_campaign_sameness, n_date_in_note
    FROM invitations
    UNION ALL
    -- The same rows again under one label, so each campaign gets a total line.
    SELECT campaign_name, 'ALL', voice_src, draft_original, sent_text, relation_state, draft_chars,
           n_label_echo, n_stat_hook, n_content_compliment, n_location_mention,
           n_campaign_sameness, n_date_in_note
    FROM invitations
)
SELECT
    r.campaign_name,
    r.mode,
    count(*)                                                        AS drafts,
    count(*) FILTER (WHERE r.voice_src LIKE 'rep%')                 AS voice_rep,
    count(*) FILTER (WHERE r.voice_src LIKE 'org%' OR r.voice_src = 'brand') AS voice_brand,
    count(*) FILTER (WHERE r.voice_src = 'none')                    AS voice_none,
    count(*) FILTER (WHERE r.draft_chars > 300)                     AS over_cap,
    -- sent = the dispatch recorded what went out
    count(*) FILTER (WHERE r.sent_text IS NOT NULL)                 AS sent,
    count(*) FILTER (
        WHERE r.sent_text IS NOT NULL
          AND r.draft_original IS NOT NULL
          AND btrim(r.sent_text) IS DISTINCT FROM btrim(r.draft_original)
    )                                                               AS edited,
    round(
        100.0 * count(*) FILTER (
            WHERE r.sent_text IS NOT NULL
              AND r.draft_original IS NOT NULL
              AND btrim(r.sent_text) IS DISTINCT FROM btrim(r.draft_original)
        ) / NULLIF(count(*) FILTER (WHERE r.sent_text IS NOT NULL AND r.draft_original IS NOT NULL), 0),
        1
    )                                                               AS edit_rate_pct,
    count(*) FILTER (WHERE r.relation_state = 'connected')          AS connected,
    round(
        100.0 * count(*) FILTER (WHERE r.relation_state = 'connected')
        / NULLIF(count(*) FILTER (WHERE r.sent_text IS NOT NULL), 0),
        1
    )                                                               AS accept_rate_pct,
    -- The four the panel and G21 care about, named rather than aggregated, so a
    -- non-zero number says which rule fired without a second query.
    sum(r.n_label_echo)          AS lint_label_echo,
    sum(r.n_stat_hook)           AS lint_stat_hook,
    sum(r.n_content_compliment)  AS lint_content_compliment,
    sum(r.n_location_mention)    AS lint_location_mention,
    sum(r.n_campaign_sameness)   AS lint_campaign_sameness,
    sum(r.n_date_in_note)        AS lint_date_in_note
FROM rows_with_rollup r
GROUP BY r.campaign_name, r.mode
ORDER BY r.campaign_name, (r.mode = 'ALL') DESC, r.mode;
