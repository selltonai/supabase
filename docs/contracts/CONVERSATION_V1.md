<!-- Copy of sellton-planning lanes/CONTRACT_CONVERSATION_V1.md (D1-4). The planning repo is the source; change both in one go. -->

# The conversation contract, v1.2

**Current version: 1.2 (2026-11-16, D1-4), additive over 1.0.** Everything marked **new 1.2** is what the engine already
serves at `sellton-new-engine` `stage` `e64fea74`, fixed as the contract (GAP-1002, GAP-1008, GAP-1010, GAP-1022; web
G-W37, G-W39, G-W41, G-W49, G-W50). Nothing in 1.0 is renamed or removed. The proposed `/next` and `/dashboard` stay
proposed (section 8) until lane E builds them.

**Date:** 2026-10-24. **Owner:** lane D (Zoran). **Tested by:** lane E (the engine serves it) and lane W (the door renders it); lane A already consumes it. **Source:** the engine's `api/plays.py` models at a9d0d81e (`PlayReply`, `MessageOut`, `QuestionOut`, `WaitingOut`, `LookingOut`, `SummaryOut`, `FeedItem`, `PlayInputIn`), fixed as a contract, plus the additions of the architecture document section 6 (marked **new**). Additive changes bump the minor (1.1, 1.2); a removal or a changed meaning bumps the major and waits for E and W.

## 1. Principles

- One conversation, two doors. The engine returns messages, cards and at most one open question; a door renders them and sends words or a choice back. A door never invents a choice, a line or a default.
- A choice is an `alternative`, not a tap: `say` carries the words the user would have said; the door shows a button or a chip and sends the words back.
- The question id travels back with the answer; a stale answer is `409 question_changed`.
- Language comes from the person's settings (`member_settings.language`), not from a header. Until the phone build that reads settings is out, the engine honours `Accept-Language` when it is present (transition, removed at major 2).
- Reads carry `ETag`; the same read with `If-None-Match` answers `304`. A thread read with `?after=<message id>` returns only the newer lines and says so.

**Who is calling (added 2026-10-27, Q-W01).** Every route takes Clerk's JWT as `Authorization: Bearer`; the engine resolves the organisation, the user, the switch row and the roles from it, and every query is scoped by the organisation at the store layer. The phone calls the engine's hostname directly. The web door calls through its own origin: a Next.js route `src/app/api/engine/[...path]` forwards the method, the path, the query, the body and the `Authorization` header unchanged, and returns the status, `ETag`, `Retry-After` and the body unchanged; it has no logic, no cache and no retry, and it is the door's only API route for the engine. The engine's hostname is never in a browser.

## 2. Routes

| Method, path | Takes | Returns | Note |
|---|---|---|---|
| `POST /plays` | `NewPlayIn {text?}` | `PlayReply` (201) | the first words make the play and are answered in the same call |
| `POST /plays/{id}/input` | `PlayInputIn` | `PlayReply` | one turn: words, a choice, a confirm, links; `question_id` required when answering a question |
| `POST /plays/{id}/input` with multipart | `photos[]`, `text?` | `PlayReply` | business cards (today's `/cards` folds into `input` at 1.1) |
| `POST /plays/{id}/input` **new 1.1** | `people[]` (pasted or dropped: name, email, company, linkedin), `files[]` | `PlayReply` | E-28; same screening and batch readback as cards |
| `GET /plays` | | `Feed` | ETag |
| `GET /plays/{id}/messages?after=` | | `PlayReply` | ETag; `after` null means the whole thread |
| `POST /plays/{id}/delete` | `{keep: bool}` | `Deleted` | a second delete answers the same |
| `POST /plays/{id}/rename` | `{name}` | `PlayReply` | |
| `POST /plays/{id}/undo` | | `PlayReply` | within the undo window after a confirm |
| `POST /plays/clear` | | `{cleared}` | the caller's drafts |
| `POST /ask` | `AskIn {text}` | `AskOut` | home's chat: an answer, or a play to open with words, or a new play |
| `GET /today` | | `Today {line, items[], older[], feedback?}` | no model call |
| `GET /plays/{id}/stats` | | `Stats` | |
| `GET /people`, `/people/{id}`, `/companies`, `/companies/{id}` | | directory models | unchanged from `api/directory.py` |
| `GET /me`, `/settings`, `PATCH /settings` | | | language lives here from 1.1 |
| `PATCH /plays/{id}/settings` **new 1.2** | `PlaySettingsIn {autonomous?: bool \| null, followups?: {on?: bool, count?: int, approved?: cancel \| send}}` (unknown keys refused) | `PlayReply` (with `settings`) | the play's own Autonomous and follow-ups (S450); `autonomous: null` follows the user's switch; a key left out is unchanged; follow-ups switched off while approved ones wait answer 409 `approved_waiting` until `approved` says cancel or send (S451). `angles` stays off (B-1029) until a later version names it |
| `GET /plays/overview` **new 1.2** | | `Overview` | the week and every play's numbers in one call (S229) |
| `GET /stats` **new 1.2** | | `WeekStats` | the week's line |
| `GET /plays/{id}/stats` **1.2: fields fixed** | | `Stats` | was named with no field in 1.0 (GAP-1010) |
| `POST /onboarding/website` **new 1.2** | `{domain}` (max 253) | `WebsiteOut` (202) | research starts; poll `GET /onboarding/card` after `retry_after` |
| `POST /onboarding/intro` **new 1.2** | `{text}` | `{saved: bool}` | |
| `POST /onboarding/answers` **new 1.2** | `{topic, text}` | `{saved: true, topic}` | `topic`: `company_name \| what_we_sell \| who_buys \| why_they_buy \| approach \| writing \| voice_sample \| never_say \| company_address` |
| `GET /onboarding/card` **new 1.2** | | `CardPending \| CardShown` | |
| `POST /onboarding/card` **new 1.2** | `CardIn {approve?, correction?, edit?: {field, text}}` (one of them) | `CardPending \| CardShown \| CardApproved` | `edit.field`: `company_name \| what_we_sell \| to_whom \| edge \| approach \| writing` |
| `GET /onboarding/sample` **new 1.2** | | `SampleShown \| SampleNone \| SamplePending` | 404 `sample_off` while the engine's sample is off |
| `POST /onboarding/sample` **new 1.2** | `{edit: {subject?, body}}` (subject max 300) | `SampleShown` | |
| `POST /onboarding/sample/voice-line` **new 1.2** | `{accept: bool}` | `CardShown` | |
| `GET /mailbox` **new 1.2** | | `Mailbox` | read-only; Settings > Connections |
| `POST /mailbox/connect` **new 1.2** | `{return_url?, provider?: gmail \| outlook \| other}` | `ConnectLink {url, kind: create \| reconnect}` | the door opens `url`; the engine sends the person back to `return_url` (an app link) |
| `POST /mailbox/resume` **new 1.2** | | `{resumed: true}` | 404 `not_paused` when sending isn't paused |
| `GET /conversations?tab=focus\|sent\|received\|waiting` **new 1.2** | | `Conversations` | what the engine built for A14 (S187); replaces section 8's proposed `/conversations` shape |
| `GET /conversations/{play_id}/{contact_id}` **new 1.2** | | `ConversationThread` | one person's thread in one play |

Errors, every route: `{detail: <code>, line: <sentence in the person's language>, request_id}`; `X-Request-Id` on every response. Codes the door must handle: `question_changed` (409), `play_busy` (409), `play_canceled` (409), `play_not_found` (404), `limit_reached` (429), `too_many_requests` (429), `brain_unavailable` (503), `database_unavailable` (503), `internal_error` (500). A door shows `line` as it is.

**New 1.2, the onboarding, mailbox and sample codes:** `no_active_org` (409), `start_with_the_website` (409), `no_card_yet` (409), `no_sample_yet` (409), `no_voice_line` (409), `sample_off` (404), `not_paused` (404), `bad_domain`, `empty_intro`, `empty_answer`, `bad_address`, `approve_or_correction`, `bad_edit`, `return_url_not_an_app_link` (422), `onboarding_unavailable`, `writer_unavailable`, `card_unavailable`, `mailbox_unavailable`, `mailbox_store_unavailable` (503). A code a door doesn't know is shown by its `line` (when the body has one) or as the generic error; never retried on its own.

## 3. Shapes

```yaml
PlayReply:
  play_id: string
  name: string
  status: draft | active | canceled | done
  turn: string                      # engine-internal; a door never branches on it
  pending_question: Question | null
  messages: [Message]
  waiting: Waiting | null
  summary: Summary
  paused: bool
  looking: Looking | null
  after: string | null              # the message id these come after; null = whole thread
  # new 1.2 (all additive; a door that doesn't draw one ignores it):
  event: {name, start?, end?, city?, booths: bool} | null    # an event play's event and its booth list (S194)
  understood: {line, parts: {roles, companies, kind, where, size, goal}} | null   # what the play read in the ask (S424); each part string or null
  delete: {people: int, asks_why: bool} | null      # what a delete would do (S422): its N people kept or removed; a cancel asks why once an email went
  undo: {kind: delete | never_write, path, until} | null    # an Undo for 30 seconds (S422): POST `path` before `until` (ISO); past `until`, none
  signals: [object]                 # the signals of its companies still in it, newest 3 a company; on GET /plays/{id}/messages only, else []
  target_count: int | null          # how many the ask wants ("find me 20 ..."), for "Found 12 of 20"; null when it names no number
  stopped_because: string | null    # why the play stopped, one plain line in the person's language; null while it runs
  stopped_at: string | null         # ISO; null while it runs or when never recorded
  settings: PlaySettings | null     # on GET /plays/{id}/messages and PATCH /plays/{id}/settings only, else null

PlaySettings:                       # new 1.2 (S450, S451)
  autonomous: bool | null           # the play's own choice; null follows the user's switch
  autonomous_effective: bool
  autonomous_allowed: bool          # true when it may be set (5 approved, or the user's switch on)
  followups: {on: bool, count: int, most: int, days: [int, int], days_min: int, days_max: int,
              dates: [string], can_raise: bool}   # dates: each step's first day (ISO), empty before the plan

Message:
  id: string
  role: user | sellton
  text: string | null
  card: Card | null
  refs: object | null               # quiet: true marks a line never spoken aloud
                                    # new 1.2: decided: {sent, scheduled, skipped} on a confirm's line
  created_at: string                # ISO 8601

Question:
  id: string
  kind: confirm_send | offer | turn
  text: string
  alternatives: [Alternative]

Alternative:                        # the door renders text; sends back what the kind says
  kind: say | start | cards | wait | reply | roles | draft | signal | connect_mailbox | add_card
        | raise_cap | suggestion | send_in_a_week | reply_draft | list    # list: new 1.1
  text: string
  words: string | null              # say, start: the words to send back
  payload: object | null            # the rest: sent back as `choice`

PlayInputIn:
  text: string | null
  confirm: bool | null
  choice: object | null             # an Alternative's payload, with its kind
  links: [{url, label}] | null      # max 3
  question_id: string | null
  people: [{name, email, company, linkedin}] | null   # new 1.1, max 300
  files: [upload] | null                               # new 1.1

Waiting:
  kind: person | companies | people | people_first | more | drafts | people_at
  retry_after_seconds: int | null

Looking:
  kind: people | people_first
  companies: int
  more: int

Summary:
  companies: int
  people: int
  sent: int | null
  replied: int
  next_followup_at: string | null

FeedItem:
  play_id, name, status, turn, last_message: Message | null, unread: bool, paused: bool, contact_id: string | null
  autonomous: bool, autonomous_label: string | null      # new 1.2
Feed:
  plays: [FeedItem], line: string | null                 # line: new 1.2

Deleted:                            # new 1.2 fields: people, undo_until
  play_id, deleted: bool, kept: bool, people: int, undo_until: string | null

PlayInputIn, new 1.2:
  draft_id: string | null           # the draft card a tap came from (its message id); a replaced draft is refused (S320)
  shared: {kind: url | contact | text, ...} | null   # one thing shared into Sellton (S188); too big 413 `too_big`, another kind 422
```

### 3.1 New 1.2: the play's numbers (`GET /plays/{id}/stats`, GAP-1010)

```yaml
Stats:
  people_found: int
  people_emailed: int
  emails_sent: int | null
  emails_waiting: int
  emails_planned: int | null
  next_email_at: string | null
  replied: int
  reply_rate: int | null            # per 100
  replies_by_kind: {<kind>: int}    # S73's dict, kept as it is
  kind_labels: {<kind>: string}
  out_of_office: int
  by_email: [{sequence: int, label, sent: int, replied: int}]
  meetings: int
  calls: int
  notes: int
  bounced: int
  opted_out: int
  members_by_status: {<status>: int}       # status: to_write | waiting | sent | replied | meeting | not_now | opted_out | bounced | held
  companies_by_status: {<status>: int}     # the same keys
  status_labels: {<status>: string}        # in the play's language
  conversion: Conversion | null
  pending: [{reason: waiting | scheduled | paused | held, count: int, at: string | null, reasons: [string], pace: int | null, line}]
  send_waiting: {label, inputs: [{play_id, question_id, input}], need_yes: int} | null   # "Send the waiting ones"; null when nothing waits

Conversion:
  first_emails: int
  replies: int
  positive_replies: int
  meetings: int
  outcome: string
  replies_per_100: int | null
  positive_per_100: int | null
  meetings_per_100_replies: int | null
  outcome_per_100: int | null
  replies_by_kind: [{kind, label, count: int, positive: bool}]
    # all six kinds, always, in this order: meeting, interested, question, not_now, other, not_interested;
    # label in the play's language; positive for every kind but not_interested; the counts add up to `replies`.
    # The same name as S73's top-level dict, but this one is a list inside `conversion` (E's ASK 2026-11-06).

WeekStats:   {since, emails: int | null, replies: int, meetings: int, line}
Overview:    {week: WeekStats, plays: [{play_id, name, state: needs_you | running | paused | stopped,
              numbers: {companies, sent: int | null, replied, reply_rate: int | null, meetings}, next: {line, at} | null, needs: string | null}]}
```

### 3.2 New 1.2: onboarding (GAP-1008, web G-W39)

```yaml
WebsiteOut:     {status: researching, domain, retry_after: int}
CardPending:    {pending: true, waiting_for: research | intro | writer, retry_after: int | null}
CardShown:      {pending: false, company_name, what_we_sell, to_whom, edge, verticals: [string], line, sources: [string],
                 approved: bool, approach: string, writing: string}
CardApproved:   {approved: true, written: bool, kb_seed: object}
SampleShown:    {shown: true, company: {name, domain}, to, subject, body, language: en | de, edited: bool,
                 voice_ask: {language: en | de, topic: voice_sample, line} | null, voice_line: {line, was} | null}
SampleNone:     {shown: false, why: no_company | writer}
SamplePending:  {pending: true, waiting_for: brain | writer, retry_after: int | null}
```

A door tells the union members apart by `pending`, `approved` and `shown`, never by which fields are present.

### 3.3 New 1.2: the mailbox (GAP-1022, web G-W49)

```yaml
Mailbox:
  status: none | connected | disconnected
  email: string | null
  reason: string | null
  since: string | null
  checked_at: string | null
  refused: {email, at, message} | null
  paused: {since, bounced: int, of: int} | null
  deliverability: {domain, checked_at: string | null, provider, spf: bool | null, dkim: bool | null, dmarc: bool | null} | null
  message: string | null
  why: no_mail_google | no_mail | null
```

### 3.4 New 1.2: conversations (A14, S187)

```yaml
Conversations:
  tab: focus | sent | received | waiting
  items: [ConversationItem]
  counts: {focus: int, sent: int, received: int, waiting: int}
  line: string | null

ConversationItem:
  contact_id, play_id, name, company, label, label_text, line
  at: string | null
  email_id: string | null
  group: answer | meeting | question | not_now | stopped | null
  read: string | null
  action: object | null             # rendered as the engine sent it
  actions: [object] | null
  later: object | null

ConversationThread:
  play_id, contact_id, name, company, play_name
  messages: [{kind: sent | received | scheduled, subject, text, at: string | null, goes_at: string | null, open_url: string | null}]
  reply: {email_id, draft: Draft | null, readback: bool, group: (as above) | null, read: string | null, action: object | null} | null
  email: {draft: Draft | null, readback: bool} | null
  can_reply: bool
  why_not: erased | bounced | unsubscribed | colleague | null
  question: string | null

Draft: {id: string | null, subject, body, files: [{id, name, size: int}], fact: Fact | null}
```

## 4. Cards (by `card.kind`)

Existing: `company`, `person`, `draft`, `followup_draft`, `reply_draft`, `readback`, `signal`, `offer`, `wait`, `roles`, `connect_mailbox`, `add_card`, `raise_cap`, `reminder`, `missed`, `start`, `one_reminder`, `sent`. Each card's fields are the engine's today (`checked` with `line` and `sources_line` on the three draft cards; `photo_url`, `mobile`, `mobile_status` on a person; `event` on a signal; `employees`, `match_reason`, `logo` on a company).

**New 1.1, `list`:** `{kind: "list", list_id, name, count, running: bool, shown: int}`. The engine sends it in place of company cards when a play's companies exceed the door's cap (the phone's `MAX_COMPANIES_PER_PLAY`, 50; the web's none). The phone shows the count and the first ten; the web opens the list view with the chat as control. The question that follows (`Keep these?`) is the same.

**New 1.2, kinds the engine already writes** (GAP-1002 (2), found in lane E's recordings): `reply`, `add_link`, `called`, `cards`, `edit`, `skip_followup`, `attach`, `suggestion`. Until a door draws one, rule 5 applies (rendered as text). The phone's `angles` kind is **not** in 1.2: the engine keeps it off (`ANGLES`, B-1029) until a later version names it.

**New 1.2, card keys** (all optional; a door that doesn't draw one ignores it):

- `company`: `close: bool`, the company meets the ask only in part (its kind, where or size against the play's reading of the ask; S446), so "Drop the close matches" can drop it.
- `draft`, `followup_draft`, `reply_draft`: `fact: Fact | null`, the fact the draft is built on, as a span of its own body (S440).
- `draft`, `readback`: `left_out: [{name, why}]`, whom the draft queue left out and why (S440), in the person's language.

```yaml
Fact:   {text, start: int, end: int, source: {kind, name, url: string | null, date: string | null}}
        # always literally in the body: body[start:end] == text; null when no fact is kept or its sentence was edited out
```

## 5. Rendering rules a door keeps

1. Alternatives in the engine's order; never add, drop or reorder; `say` as the words; others as `choice`.
2. One open question at a time; its id on the answer.
3. `quiet` lines are shown, never spoken (voice doors).
4. `waiting` shows a wait state and polls with `after=` at `retry_after_seconds`; `looking` is a quiet header line.
5. A card's unknown `kind` renders as text, never crashes; a test in each door pins that every kind the engine writes is known.
6. `line` on an error is shown as the engine wrote it.

## 6. Table contracts (lane D keeps these in the architecture document, section 3)

The door never reads tables. The engine's stores are the contract between E and D: `engine_actions`, `engine_send_counters`, `play_messages` (exist); `play_members`, `person_events`, `member_settings`, `connections`, `signals`, `account_people`, `account_relations`, `play_templates`, `playbook_entries`, `play_steps`, `tool_log`, `engine_limits`, `engine_pacing`, `engine_workers`, `chat_lines`, `feedback`, `workspace_switch` (migration steps 0 to 5). Each lands with a contract test in the pg suite before the engine reads it.

## 7. Versions

| Version | Date | Change |
|---|---|---|
| 1.0 | 2026-10-24 | today's `PlayReply` and routes fixed as the contract |
| 1.1 | with migration step 6 | `list` card and alternative; `people[]` and `files[]` on input; language from settings; `/cards` folded into `input` |
| 1.2 | 2026-11-16 (D1-4) | what the engine serves at `e64fea74`, fixed: the `PlayReply` fields `event`, `understood`, `delete`, `undo`, `signals`, `target_count`, `stopped_because`, `stopped_at`, `settings`; `refs.decided`; the card kinds `reply`, `add_link`, `called`, `cards`, `edit`, `skip_followup`, `attach`, `suggestion`; the card keys `close`, `fact`, `left_out`; `PATCH /plays/{id}/settings`; the play's `Stats` with `conversion.replies_by_kind`; `/plays/overview`, `/stats`; the onboarding routes and the sample; the mailbox routes; `/conversations` as built. All additive |
| 1.2+ (proposed, D1-11) | when lane E builds them | `/next`, `/dashboard` and the `Task`, `Tile` shapes (section 8); `retry_after_seconds` on the `database_unavailable` error; `POST /conversations/{thread_id}/match`. Lane D fixes them with E and W before W2 builds Next and the dashboard tiles (W2-3, W2-4) |
| 1.3 | wave 2 (D1-22) | the interpretation card's chips, the autonomy scope (with "yours to send" as the fourth sending answer, and the draft's "yours to send" state on the play), the per-member language field, the interviewer card, the takeover question kind, the batch digest line (spec 7.6.10) |
| 1.4 | wave 3 (D1-26) | the LinkedIn cards, the network list card, the extension's shapes |

## 8. Proposed 1.2 (planning session, 2026-10-26; lane D decides the shapes with E and W)

The screens Next (A8), the dashboard (A13) and Conversations (A14) need routes the contract doesn't have. All read-only routes return ETag and carry no model call; the door renders, never computes.

| Method, path | Takes | Returns | Note |
|---|---|---|---|
| `GET /next?view=mine\|team&play=&deal=&kind=&overdue=` | | `Next {line, one: Task \| null, groups: [{key, label, tasks[]}], proposals: Task[], counts: {needs_me, overdue}}` | the whole screen in one call; groups in the engine's order (Part 7.9) |
| `POST /next/{id}/do` | | `TaskAction {kind: send\|call\|open_thread\|open_brief\|open_play, payload}` | the prepared action; `send` takes the draft id and goes through the normal yes |
| `POST /next/{id}/snooze` | `{until: date \| "tomorrow" \| "next_week"}` | `Task` | |
| `POST /next/{id}/done`, `/dismiss`, `/accept` | | `Task` | `accept` turns a proposal into a task; `dismiss` records the reason key |
| `POST /next/{id}/assign` | `{user_id}` | `Task` | admin, or the owner handing over |
| `POST /next/bulk` | `{ids[], action, until?}` | `{changed}` | snooze or assign several |
| `GET /dashboard?period=&rep=&pipeline=&play=` | | `Dashboard {tiles: Tile[], next: Task[], pipeline, week, plays, team, network}` | one call; every number with `href` to its list |
| `GET /conversations?filter=needs_me\|waiting\|channel=\|play=\|owner=\|unmatched&after=` | | `Conversations {threads: Thread[], counts}` | A14's list; a thread is messages across channels with the draft and the person's memory line |
| `POST /conversations/{thread_id}/match` | `{person_id}` | `Thread` | an unmatched reply placed by the user |

```
Task:
  id, kind: reply|call|email|meeting|deal|signal|reminder|lead|proposal, action: string (five words), why: string,
  person: {id, name} | null, company: {id, name} | null, play_id: string | null, deal_id: string | null,
  due_at: string | null, best_hour: string | null, owner: {id, initials}, proposed: bool, source: {kind, id},
  prepared: {kind: draft|number|brief|thread, id} | null

Tile:
  key: replies|leads|meetings|next|waiting|signals, counts: [{label, n, href}], change: string | null
```

Rendering rules added: a `Task.prepared` of unknown kind renders as "open"; a tile with no `href` is text; the door never reorders groups or tiles.

**Status 2026-11-16:** `/conversations` is built and fixed in 1.2 with the engine's own shape (section 3.4), which
replaces the `Thread` row above; `/next` and `/dashboard` are not on the engine yet and stay proposed.

## 9. Open points (2026-11-16, lane D)

1. **A kindless alternative** (GAP-1002 (3)): the reply's `offer` question carries one alternative `{"email_id": ...}`
   with neither `kind` nor `text`, against section 3. Either the engine gives it a kind and text, or the contract
   names it. Asked of lane E; until then a door skips an alternative with no `text` rather than draw an empty chip.
2. **Routes that differ from section 2** (found at 1.2): the engine renames with `PATCH /plays/{id}` `{name}`, not
   `POST /plays/{id}/rename`; `POST /plays/{id}/cards` is still its own route (1.1 folds it into `input` with step 6);
   and it serves `POST /plays/{id}/restore`, `/discard`, `/attachments` and `POST /people/{contact_id}/chat`, which no
   version names yet. Not changed in 1.2: which side moves is for E and W.
3. **Ten 1.0 card kinds have no recording** (GAP-1002 (4)): `offer`, `wait`, `roles`, `add_card`, `raise_cap`,
   `reminder`, `missed`, `start`, `one_reminder`, `sent`. They stay in the contract; lane Q's journeys should reach them.
