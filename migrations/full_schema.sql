

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


COMMENT ON SCHEMA "public" IS 'contact_conversations table removed - conversations now fetched from external API';



CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pg_trgm" WITH SCHEMA "public";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "vector" WITH SCHEMA "public";






CREATE TYPE "public"."activity_type" AS ENUM (
    'email_sent',
    'email_received',
    'call',
    'meeting',
    'note',
    'task',
    'deal_created',
    'deal_updated',
    'status_change',
    'email_draft_created',
    'email_reply_sent',
    'campaign_added'
);


ALTER TYPE "public"."activity_type" OWNER TO "postgres";


CREATE TYPE "public"."api_provider" AS ENUM (
    'b2b_enrichment',
    'exa',
    'perplexity',
    'openai',
    'deepseek',
    'togetherai'
);


ALTER TYPE "public"."api_provider" OWNER TO "postgres";


CREATE TYPE "public"."campaign_status" AS ENUM (
    'draft',
    'active',
    'paused',
    'completed',
    'cancelled'
);


ALTER TYPE "public"."campaign_status" OWNER TO "postgres";


CREATE TYPE "public"."channel_type" AS ENUM (
    'email',
    'whatsapp',
    'messenger',
    'phone_sms',
    'phone',
    'linkedin',
    'twitter',
    'other'
);


ALTER TYPE "public"."channel_type" OWNER TO "postgres";


CREATE TYPE "public"."company_activity_type" AS ENUM (
    'company_verification_approved',
    'company_verification_declined',
    'note_added',
    'meeting_prepared',
    'contact_added',
    'campaign_added',
    'icp_score_updated',
    'company_updated'
);


ALTER TYPE "public"."company_activity_type" OWNER TO "postgres";


CREATE TYPE "public"."contact_type" AS ENUM (
    'user',
    'lead',
    'customer',
    'prospect'
);


ALTER TYPE "public"."contact_type" OWNER TO "postgres";


CREATE TYPE "public"."email_status" AS ENUM (
    'draft',
    'scheduled',
    'sent',
    'delivered',
    'opened',
    'clicked',
    'replied',
    'bounced',
    'failed'
);


ALTER TYPE "public"."email_status" OWNER TO "postgres";


CREATE TYPE "public"."file_category_enum" AS ENUM (
    'documents',
    'transcripts',
    'internal_documents',
    'sales_papers',
    'sait_guidelines',
    'brand_guidelines',
    'case_study',
    'sales_scripts'
);


ALTER TYPE "public"."file_category_enum" OWNER TO "postgres";


CREATE TYPE "public"."plan" AS ENUM (
    'free',
    'pro',
    'free_trial_over'
);


ALTER TYPE "public"."plan" OWNER TO "postgres";


CREATE TYPE "public"."task_status" AS ENUM (
    'pending',
    'in_progress',
    'completed',
    'cancelled',
    'scheduled',
    'failed'
);


ALTER TYPE "public"."task_status" OWNER TO "postgres";


CREATE TYPE "public"."task_type" AS ENUM (
    'review_draft',
    'meeting',
    'company_verification',
    'email_generation_processing'
);


ALTER TYPE "public"."task_type" OWNER TO "postgres";


COMMENT ON TYPE "public"."task_type" IS 'Valid task types for the tasks table:
- review_draft: Email drafts awaiting review/approval before sending
- meeting: Meeting scheduling and coordination tasks
- email_generation_processing: Lock task to prevent duplicate email generation during webhook processing';



CREATE TYPE "public"."usage_context_type" AS ENUM (
    'agent_run',
    'direct_api',
    'batch_processing'
);


ALTER TYPE "public"."usage_context_type" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_email_status_activity"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  activity_title TEXT;
  activity_description TEXT;
  activity_type_name activity_type;
BEGIN
  -- Only create activities for certain status changes
  IF TG_OP = 'UPDATE' AND OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  -- Determine activity type and title based on new status
  CASE NEW.status
    WHEN 'sent' THEN
      activity_type_name := 'email_sent';
      activity_title := 'Campaign email sent';
      activity_description := COALESCE('Email "' || NEW.subject || '" sent successfully', 'Campaign email sent');
      
    WHEN 'delivered' THEN
      activity_type_name := 'email_sent'; -- We'll use email_sent type for delivered
      activity_title := 'Email delivered';
      activity_description := COALESCE('Email "' || NEW.subject || '" was delivered', 'Campaign email delivered');
      
    WHEN 'opened' THEN
      activity_type_name := 'email_sent'; -- We'll use email_sent type for opened
      activity_title := 'Email opened';
      activity_description := COALESCE('Email "' || NEW.subject || '" was opened by recipient', 'Campaign email opened');
      
    WHEN 'replied' THEN
      activity_type_name := 'email_received';
      activity_title := 'Received reply to campaign email';
      activity_description := COALESCE('Reply received for email "' || NEW.subject || '"', 'Reply received to campaign email');
      
    WHEN 'bounced' THEN
      activity_type_name := 'email_sent';
      activity_title := 'Email bounced';
      activity_description := COALESCE('Email "' || NEW.subject || '" bounced', 'Campaign email bounced');
      
    ELSE
      -- No activity for draft, scheduled, failed
      RETURN NEW;
  END CASE;

  -- Insert the activity record
  INSERT INTO contact_activities (
    contact_id,
    organization_id,
    activity_type,
    title,
    description,
    metadata,
    occurred_at
  ) VALUES (
    NEW.contact_id,
    NEW.organization_id,
    activity_type_name,
    activity_title,
    activity_description,
    jsonb_build_object(
      'campaign_email_id', NEW.id,
      'campaign_id', NEW.campaign_id,
      'email_status', NEW.status,
      'subject', NEW.subject,
      'message_id', NEW.message_id,
      'thread_id', NEW.thread_id
    ),
    CASE NEW.status
      WHEN 'sent' THEN NEW.sent_at
      WHEN 'delivered' THEN NEW.delivered_at
      WHEN 'opened' THEN NEW.opened_at
      WHEN 'replied' THEN NEW.replied_at
      WHEN 'bounced' THEN NEW.bounced_at
      ELSE NOW()
    END
  );

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."create_email_status_activity"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."create_email_status_activity"() IS 'Automatically creates contact activities when email status changes';



CREATE OR REPLACE FUNCTION "public"."debug_pipeline_stages"("org_id" "text") RETURNS TABLE("stage" "text", "count" bigint, "raw_stages" "text"[])
    LANGUAGE "plpgsql" STABLE
    AS $$
BEGIN
  RETURN QUERY
  WITH raw_data AS (
    SELECT 
      pipeline_stage,
      COUNT(*) as cnt
    FROM contacts
    WHERE organization_id = org_id
    GROUP BY pipeline_stage
  ),
  normalized_data AS (
    SELECT 
      CASE 
        WHEN pipeline_stage IS NULL OR pipeline_stage = '' THEN 'Unknown'
        ELSE UPPER(TRIM(pipeline_stage))
      END as normalized_stage,
      COUNT(*) as cnt
    FROM contacts
    WHERE organization_id = org_id
    GROUP BY CASE 
      WHEN pipeline_stage IS NULL OR pipeline_stage = '' THEN 'Unknown'
      ELSE UPPER(TRIM(pipeline_stage))
    END
  )
  SELECT 
    nd.normalized_stage as stage,
    nd.cnt as count,
    ARRAY_AGG(DISTINCT rd.pipeline_stage) as raw_stages
  FROM normalized_data nd
  LEFT JOIN raw_data rd ON (
    CASE 
      WHEN rd.pipeline_stage IS NULL OR rd.pipeline_stage = '' THEN 'Unknown'
      ELSE UPPER(TRIM(rd.pipeline_stage))
    END = nd.normalized_stage
  )
  GROUP BY nd.normalized_stage, nd.cnt
  ORDER BY nd.cnt DESC;
END;
$$;


ALTER FUNCTION "public"."debug_pipeline_stages"("org_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."filter_companies_for_campaign"("p_organization_id" "text", "p_company_data" "jsonb") RETURNS TABLE("company_data" "jsonb", "is_already_used" boolean, "existing_company_id" "uuid")
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    company_item JSONB;
    existing_company RECORD;
BEGIN
    -- Loop through each company in the input data
    FOR company_item IN SELECT * FROM jsonb_array_elements(p_company_data)
    LOOP
        -- Check if company already exists and has been used for outreach
        SELECT id, name, used_for_outreach INTO existing_company
        FROM companies 
        WHERE organization_id = p_organization_id 
        AND (
            (company_item->>'linkedin_url' IS NOT NULL AND linkedin_url = company_item->>'linkedin_url') OR
            (company_item->>'name' IS NOT NULL AND LOWER(name) = LOWER(company_item->>'name')) OR
            (company_item->>'domain' IS NOT NULL AND domain = company_item->>'domain')
        );
        
        IF FOUND THEN
            RETURN QUERY SELECT 
                company_item,
                COALESCE(existing_company.used_for_outreach, FALSE),
                existing_company.id;
        ELSE
            RETURN QUERY SELECT 
                company_item,
                FALSE,
                NULL::UUID;
        END IF;
    END LOOP;
END;
$$;


ALTER FUNCTION "public"."filter_companies_for_campaign"("p_organization_id" "text", "p_company_data" "jsonb") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."filter_companies_for_campaign"("p_organization_id" "text", "p_company_data" "jsonb") IS 'Filters company data to identify which companies have already been used for outreach';



CREATE OR REPLACE FUNCTION "public"."get_campaign_contacts"("p_campaign_id" "uuid") RETURNS TABLE("contact_id" "uuid", "contact_name" "text", "contact_email" "text", "company_name" "text", "job_title" "text", "added_at" timestamp with time zone, "source_type" "text", "relationship_status" "text", "created_from_campaign" boolean)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        c.id as contact_id,
        c.name as contact_name,
        c.email as contact_email,
        c.company_name,
        c.job_title,
        cc.added_at,
        cc.source_type,
        cc.status as relationship_status,
        cc.created_from_campaign
    FROM campaign_contacts cc
    JOIN contacts c ON c.id = cc.contact_id
    WHERE cc.campaign_id = p_campaign_id
    ORDER BY cc.added_at DESC;
END;
$$;


ALTER FUNCTION "public"."get_campaign_contacts"("p_campaign_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_campaign_contacts"("p_campaign_id" "uuid") IS 'Returns all contacts in a specific campaign with relationship details';



CREATE OR REPLACE FUNCTION "public"."get_campaign_summary"("p_campaign_id" "uuid") RETURNS TABLE("total_contacts" integer, "emails_sent" integer, "emails_delivered" integer, "emails_opened" integer, "emails_replied" integer, "meetings_booked" integer, "open_rate" numeric, "reply_rate" numeric, "meeting_rate" numeric)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  RETURN QUERY
  SELECT 
    c.total_contacts,
    c.emails_sent,
    c.emails_delivered,
    c.emails_opened,
    c.emails_replied,
    c.meetings_booked,
    CASE 
      WHEN c.emails_sent > 0 THEN ROUND((c.emails_opened::NUMERIC / c.emails_sent) * 100, 2)
      ELSE 0
    END as open_rate,
    CASE 
      WHEN c.emails_sent > 0 THEN ROUND((c.emails_replied::NUMERIC / c.emails_sent) * 100, 2)
      ELSE 0
    END as reply_rate,
    CASE 
      WHEN c.emails_sent > 0 THEN ROUND((c.meetings_booked::NUMERIC / c.emails_sent) * 100, 2)
      ELSE 0
    END as meeting_rate
  FROM campaigns c
  WHERE c.id = p_campaign_id;
END;
$$;


ALTER FUNCTION "public"."get_campaign_summary"("p_campaign_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_campaign_summary"("p_campaign_id" "uuid") IS 'Returns summary metrics for a specific campaign';



CREATE OR REPLACE FUNCTION "public"."get_companies_by_campaign"("p_organization_id" "text", "p_campaign_id" "uuid", "p_status" "text" DEFAULT NULL::"text", "p_search" "text" DEFAULT NULL::"text", "p_sort_by" "text" DEFAULT 'name'::"text", "p_sort_order" "text" DEFAULT 'asc'::"text", "p_page" integer DEFAULT 1, "p_limit" integer DEFAULT 50) RETURNS TABLE("id" "uuid", "organization_id" "text", "name" "text", "website" "text", "size" "text", "linkedin_url" "text", "description" "text", "created_at" timestamp with time zone, "updated_at" timestamp with time zone, "used_for_outreach" boolean, "phone" "text", "employee_count" integer, "logo" "text", "location" "text", "industries" "text"[], "icp_score" "jsonb", "deep_research" "jsonb", "outreach_strategy" "jsonb", "universal_name" "text", "company_type" "text", "cover" "text", "tagline" "text", "founded_year" integer, "object_urn" bigint, "followers" integer, "locations" "jsonb", "funding_data" "jsonb", "specialities" "text"[], "hashtags" "text"[], "processing_status" "text", "b2b_result" "jsonb", "blocked_by_icp" boolean, "total_count" bigint)
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_offset INTEGER;
  v_total BIGINT;
BEGIN
  v_offset := (p_page - 1) * p_limit;
  
  SELECT COUNT(DISTINCT c.id) INTO v_total
  FROM companies c
  INNER JOIN campaign_companies cc ON c.id = cc.company_id
  WHERE c.organization_id = p_organization_id
    AND cc.campaign_id = p_campaign_id
    AND cc.organization_id = p_organization_id
    AND (
      p_status IS NULL
      OR (p_status = 'approved' AND c.processing_status = 'approved' AND COALESCE(c.blocked_by_icp, false) = false)
      OR (p_status = 'processing' AND c.processing_status IN ('processing', 'pending'))
      OR (p_status = 'processed' AND (c.processing_status IN ('processed', 'approved', 'declined') OR c.blocked_by_icp = true))
      OR (p_status = 'declined' AND c.processing_status = 'declined')
      OR (p_status = 'blocked_by_icp' AND c.blocked_by_icp = true)
      OR (p_status = 'failed' AND c.processing_status = 'failed')
      OR (p_status = 'scheduled' AND c.processing_status = 'scheduled')
    )
    AND (p_search IS NULL OR p_search = '' OR c.name ILIKE '%' || p_search || '%' OR c.location ILIKE '%' || p_search || '%');

  RETURN QUERY
  SELECT 
    c.id, c.organization_id, c.name, c.website, c.size, c.linkedin_url, c.description,
    c.created_at, c.updated_at, c.used_for_outreach, c.phone, c.employee_count, c.logo,
    c.location, c.industries, c.icp_score, c.deep_research, c.outreach_strategy,
    c.universal_name, c.company_type, c.cover, c.tagline, c.founded_year, c.object_urn,
    c.followers, c.locations, c.funding_data, c.specialities, c.hashtags,
    c.processing_status, c.b2b_result, c.blocked_by_icp, v_total
  FROM companies c
  INNER JOIN campaign_companies cc ON c.id = cc.company_id
  WHERE c.organization_id = p_organization_id
    AND cc.campaign_id = p_campaign_id
    AND cc.organization_id = p_organization_id
    AND (
      p_status IS NULL
      OR (p_status = 'approved' AND c.processing_status = 'approved' AND COALESCE(c.blocked_by_icp, false) = false)
      OR (p_status = 'processing' AND c.processing_status IN ('processing', 'pending'))
      OR (p_status = 'processed' AND (c.processing_status IN ('processed', 'approved', 'declined') OR c.blocked_by_icp = true))
      OR (p_status = 'declined' AND c.processing_status = 'declined')
      OR (p_status = 'blocked_by_icp' AND c.blocked_by_icp = true)
      OR (p_status = 'failed' AND c.processing_status = 'failed')
      OR (p_status = 'scheduled' AND c.processing_status = 'scheduled')
    )
    AND (p_search IS NULL OR p_search = '' OR c.name ILIKE '%' || p_search || '%' OR c.location ILIKE '%' || p_search || '%')
  ORDER BY
    CASE WHEN p_sort_by = 'name' AND p_sort_order = 'asc' THEN c.name END ASC,
    CASE WHEN p_sort_by = 'name' AND p_sort_order = 'desc' THEN c.name END DESC,
    CASE WHEN p_sort_by = 'created_at' AND p_sort_order = 'asc' THEN c.created_at END ASC,
    CASE WHEN p_sort_by = 'created_at' AND p_sort_order = 'desc' THEN c.created_at END DESC,
    c.name ASC
  LIMIT p_limit OFFSET v_offset;
END;
$$;


ALTER FUNCTION "public"."get_companies_by_campaign"("p_organization_id" "text", "p_campaign_id" "uuid", "p_status" "text", "p_search" "text", "p_sort_by" "text", "p_sort_order" "text", "p_page" integer, "p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_contact_campaigns"("p_contact_id" "uuid") RETURNS TABLE("campaign_id" "uuid", "campaign_name" "text", "campaign_status" "text", "campaign_type" "text", "added_at" timestamp with time zone, "source_type" "text", "relationship_status" "text")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        c.id as campaign_id,
        c.name as campaign_name,
        c.status::TEXT as campaign_status,
        c.campaign_type,
        cc.added_at,
        cc.source_type,
        cc.status as relationship_status
    FROM campaign_contacts cc
    JOIN campaigns c ON c.id = cc.campaign_id
    WHERE cc.contact_id = p_contact_id
    ORDER BY cc.added_at DESC;
END;
$$;


ALTER FUNCTION "public"."get_contact_campaigns"("p_contact_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_contact_campaigns"("p_contact_id" "uuid") IS 'Returns all campaigns that a contact is part of';



CREATE OR REPLACE FUNCTION "public"."get_dashboard_stats"("p_organization_id" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'companies', jsonb_build_object(
      'total', count(*),
      'all_companies', count(*),
      'scheduled', count(*) FILTER (WHERE processing_status = 'scheduled'),
      'processing', count(*) FILTER (WHERE processing_status IN ('processing', 'pending')),
      'processed', count(*) FILTER (WHERE processing_status IN ('processed', 'approved', 'declined') OR blocked_by_icp = true),
      'approved', count(*) FILTER (WHERE processing_status = 'approved'),
      'declined', count(*) FILTER (WHERE processing_status = 'declined'),
      'blocked_by_icp', count(*) FILTER (WHERE blocked_by_icp = true),
      'failed', count(*) FILTER (WHERE processing_status = 'failed')
    ),
    'contacts', jsonb_build_object(
      'total', (SELECT count(*) FROM contacts WHERE organization_id = p_organization_id),
      'total_contacts', (SELECT count(*) FROM contacts WHERE organization_id = p_organization_id),
      'processing', (SELECT count(*) FROM contacts WHERE organization_id = p_organization_id AND processing_status IN ('pending', 'processing')),
      'completed', (SELECT count(*) FROM contacts WHERE organization_id = p_organization_id AND processing_status = 'completed')
    ),
    'tasks', (
      SELECT jsonb_build_object(
        'totalTasks', count(*),
        'pendingTasks', count(*) FILTER (WHERE status = 'pending'),
        'inProgressTasks', count(*) FILTER (WHERE status = 'in_progress'),
        'completedTasks', count(*) FILTER (WHERE status = 'completed'),
        'cancelledTasks', count(*) FILTER (WHERE status = 'cancelled'),
        'scheduledTasks', 0,
        -- Task type counts - PENDING ONLY (so they sum to pendingTasks)
        'reviewDraftTasks', count(*) FILTER (WHERE task_type::text = 'review_draft' AND status = 'pending'),
        'meetingTasks', count(*) FILTER (WHERE task_type::text = 'meeting' AND status = 'pending'),
        'companyVerificationTasks', count(*) FILTER (WHERE task_type::text = 'company_verification' AND status = 'pending'),
        'overdueTasks', count(*) FILTER (WHERE status IN ('pending', 'in_progress') AND due_date < now()),
        'dueTodayTasks', count(*) FILTER (WHERE status IN ('pending', 'in_progress') AND due_date >= date_trunc('day', now()) AND due_date < date_trunc('day', now()) + interval '1 day'),
        'dueThisWeekTasks', count(*) FILTER (WHERE status IN ('pending', 'in_progress') AND due_date >= date_trunc('week', now()) AND due_date < date_trunc('week', now()) + interval '1 week')
      )
      FROM tasks
      WHERE organization_id = p_organization_id
    )
  )
  INTO result
  FROM companies
  WHERE organization_id = p_organization_id;
  
  RETURN result;
END;
$$;


ALTER FUNCTION "public"."get_dashboard_stats"("p_organization_id" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_dashboard_stats"("p_organization_id" "text") IS 'Dashboard statistics. Task type counts (reviewDraftTasks, meetingTasks, companyVerificationTasks) now only count PENDING tasks so they sum to pendingTasks total.';



CREATE OR REPLACE FUNCTION "public"."get_organization_summary"("p_organization_id" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'tasks', jsonb_build_object(
      'total', (SELECT count(*) FROM tasks WHERE organization_id = p_organization_id),
      'pending', (SELECT count(*) FROM tasks WHERE organization_id = p_organization_id AND status = 'pending'),
      'in_progress', (SELECT count(*) FROM tasks WHERE organization_id = p_organization_id AND status = 'in_progress'),
      'completed', (SELECT count(*) FROM tasks WHERE organization_id = p_organization_id AND status = 'completed'),
      'cancelled', (SELECT count(*) FROM tasks WHERE organization_id = p_organization_id AND status = 'cancelled')
    ),
    'companies', jsonb_build_object(
      'total', count(*),
      'all_companies', count(*),
      'scheduled', count(*) FILTER (WHERE processing_status = 'scheduled'),
      'processing', count(*) FILTER (WHERE processing_status IN ('processing', 'pending')),
      'processed', count(*) FILTER (WHERE processing_status = 'processed'),
      'approved', count(*) FILTER (WHERE processing_status = 'approved'),
      'declined', count(*) FILTER (WHERE processing_status = 'declined'),
      'blocked_by_icp', count(*) FILTER (WHERE blocked_by_icp = true),
      'failed', count(*) FILTER (WHERE processing_status = 'failed'),
      'failure_reasons', (
        SELECT jsonb_object_agg(COALESCE(failure_reason, 'unknown'), cnt)
        FROM (
          SELECT failure_reason, count(*) as cnt
          FROM companies
          WHERE organization_id = p_organization_id 
            AND processing_status = 'failed'
            AND failure_reason IS NOT NULL
          GROUP BY failure_reason
        ) sub
      )
    ),
    'contacts', jsonb_build_object(
      'total', (SELECT count(*) FROM contacts WHERE organization_id = p_organization_id),
      'total_contacts', (SELECT count(*) FROM contacts WHERE organization_id = p_organization_id),
      'processing', (SELECT count(*) FROM contacts WHERE organization_id = p_organization_id AND processing_status IN ('pending', 'processing')),
      'completed', (SELECT count(*) FROM contacts WHERE organization_id = p_organization_id AND processing_status = 'completed')
    )
  )
  INTO result
  FROM companies
  WHERE organization_id = p_organization_id;
  
  RETURN result;
END;
$$;


ALTER FUNCTION "public"."get_organization_summary"("p_organization_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_sales_pipeline_analytics"("org_id" "text") RETURNS "json"
    LANGUAGE "plpgsql" STABLE
    AS $$
DECLARE
  pipeline_data JSON;
  industry_data JSON;
  location_data JSON;
  total_contacts INTEGER;
  -- Counts for conversion rate calculation (cumulative, meaning at stage OR beyond)
  count_at_or_beyond_lead INTEGER;
  count_at_or_beyond_appointment INTEGER;
  count_at_or_beyond_appointment_scheduled INTEGER;
  count_at_or_beyond_presentation INTEGER;
BEGIN
  -- Get total contacts
  SELECT COUNT(*) INTO total_contacts
  FROM contacts
  WHERE organization_id = org_id;

  -- Calculate cumulative stage counts for conversion rates
  -- These count everyone who has REACHED each stage or gone beyond it
  
  -- Count contacts at LEAD or any later stage (passed through LEAD)
  SELECT COUNT(*) INTO count_at_or_beyond_lead
  FROM contacts
  WHERE organization_id = org_id
    AND UPPER(pipeline_stage) IN (
      'LEAD',
      'APPOINTMENT_REQUESTED',
      'APPOINTMENT_SCHEDULED',
      'APPOINTMENT_CANCELLED',
      'PRESENTATION_SCHEDULED',
      'CONTRACT_NEGOTIATIONS',
      'AGREEMENT_IN_PRINCIPLE',
      'CLOSED_WON',
      'CLOSED_LOST',
      'REENGAGEMENT'
    );

  -- Count contacts at APPOINTMENT stages or beyond (passed through APPOINTMENT)
  SELECT COUNT(*) INTO count_at_or_beyond_appointment
  FROM contacts
  WHERE organization_id = org_id
    AND UPPER(pipeline_stage) IN (
      'APPOINTMENT_REQUESTED',
      'APPOINTMENT_SCHEDULED',
      'APPOINTMENT_CANCELLED',
      'PRESENTATION_SCHEDULED',
      'CONTRACT_NEGOTIATIONS',
      'AGREEMENT_IN_PRINCIPLE',
      'CLOSED_WON',
      'CLOSED_LOST',
      'REENGAGEMENT'
    );

  -- Count contacts at APPOINTMENT_SCHEDULED or beyond (for appointment → presentation conversion)
  SELECT COUNT(*) INTO count_at_or_beyond_appointment_scheduled
  FROM contacts
  WHERE organization_id = org_id
    AND UPPER(pipeline_stage) IN (
      'APPOINTMENT_SCHEDULED',
      'APPOINTMENT_CANCELLED',
      'PRESENTATION_SCHEDULED',
      'CONTRACT_NEGOTIATIONS',
      'AGREEMENT_IN_PRINCIPLE',
      'CLOSED_WON',
      'CLOSED_LOST',
      'REENGAGEMENT'
    );

  -- Count contacts at PRESENTATION or beyond
  SELECT COUNT(*) INTO count_at_or_beyond_presentation
  FROM contacts
  WHERE organization_id = org_id
    AND UPPER(pipeline_stage) IN (
      'PRESENTATION_SCHEDULED',
      'CONTRACT_NEGOTIATIONS',
      'AGREEMENT_IN_PRINCIPLE',
      'CLOSED_WON'
    );

  -- Get pipeline stages (WORKING VERSION)
  SELECT json_agg(stage_row ORDER BY count DESC)
  INTO pipeline_data
  FROM (
    SELECT 
      json_build_object(
        'stage', UPPER(COALESCE(NULLIF(TRIM(pipeline_stage), ''), 'Unknown')),
        'count', COUNT(*)::integer,
        'percentage', CASE 
          WHEN total_contacts > 0 THEN ROUND((COUNT(*)::numeric / total_contacts * 100), 2)
          ELSE 0
        END
      ) as stage_row,
      COUNT(*) as count
    FROM contacts
    WHERE organization_id = org_id
    GROUP BY UPPER(COALESCE(NULLIF(TRIM(pipeline_stage), ''), 'Unknown'))
  ) stages;

  -- Get industry distribution (safe version)
  BEGIN
    WITH company_industries AS (
      SELECT 
        UNNEST(COALESCE(c.industries, ARRAY[]::text[])) as industry,
        COUNT(DISTINCT cc.id) as contact_count
      FROM companies c
      JOIN company_contacts cc ON cc.company_id = c.id
      WHERE c.organization_id = org_id
      GROUP BY industry
      ORDER BY contact_count DESC
      LIMIT 10
    )
    SELECT json_agg(
      json_build_object(
        'industry', ci.industry,
        'count', ci.contact_count,
        'percentage', CASE 
          WHEN (SELECT SUM(contact_count) FROM company_industries) > 0 
          THEN ROUND((ci.contact_count::numeric / (SELECT SUM(contact_count) FROM company_industries) * 100), 2)
          ELSE 0
        END
      ) ORDER BY ci.contact_count DESC
    ) INTO industry_data
    FROM company_industries ci;
  EXCEPTION WHEN OTHERS THEN
    industry_data := '[]'::json;
  END;

  -- Get location distribution (safe version)
  BEGIN
    WITH location_stats AS (
      SELECT 
        ct.location,
        COUNT(*) as count
      FROM contacts ct
      WHERE ct.organization_id = org_id
        AND ct.location IS NOT NULL
        AND ct.location != ''
      GROUP BY ct.location
      ORDER BY count DESC
      LIMIT 10
    )
    SELECT json_agg(
      json_build_object(
        'location', ls.location,
        'count', ls.count,
        'percentage', CASE 
          WHEN (SELECT SUM(count) FROM location_stats) > 0
          THEN ROUND((ls.count::numeric / (SELECT SUM(count) FROM location_stats) * 100), 2)
          ELSE 0
        END
      ) ORDER BY ls.count DESC
    ) INTO location_data
    FROM location_stats ls;
  EXCEPTION WHEN OTHERS THEN
    location_data := '[]'::json;
  END;

  -- Return complete result
  RETURN json_build_object(
    'pipeline', COALESCE(pipeline_data, '[]'::json),
    'industries', COALESCE(industry_data, '[]'::json),
    'locations', COALESCE(location_data, '[]'::json),
    'totalContacts', total_contacts,
    'totalCompanies', (
      SELECT COUNT(*) FROM companies WHERE organization_id = org_id
    ),
    'averageContactsPerCompany', (
      SELECT COALESCE(ROUND(AVG(contact_count), 2), 0)
      FROM (
        SELECT COUNT(cc.id) as contact_count
        FROM companies c
        LEFT JOIN company_contacts cc ON cc.company_id = c.id
        WHERE c.organization_id = org_id
        GROUP BY c.id
      ) counts
    ),
    'companiesWithContacts', (
      SELECT COUNT(DISTINCT c.id)
      FROM companies c
      JOIN company_contacts cc ON cc.company_id = c.id
      WHERE c.organization_id = org_id
    ),
    'stageConversionRates', json_build_object(
      -- Prospect → Lead: (contacts that reached Lead or beyond) / (total contacts)
      'prospectToLead', CASE 
        WHEN total_contacts > 0 
        THEN ROUND((count_at_or_beyond_lead::numeric / total_contacts * 100), 2)
        ELSE 0
      END,
      -- Lead → Appointment: (contacts that reached Appointment or beyond) / (contacts that reached Lead or beyond)
      'leadToAppointment', CASE 
        WHEN count_at_or_beyond_lead > 0 
        THEN ROUND((count_at_or_beyond_appointment::numeric / count_at_or_beyond_lead * 100), 2)
        ELSE 0
      END,
      -- Appointment → Presentation: (contacts at Presentation or beyond) / (contacts at Appointment Scheduled or beyond)
      'appointmentToPresentation', CASE 
        WHEN count_at_or_beyond_appointment_scheduled > 0 
        THEN ROUND((count_at_or_beyond_presentation::numeric / count_at_or_beyond_appointment_scheduled * 100), 2)
        ELSE 0
      END
    )
  );
END;
$$;


ALTER FUNCTION "public"."get_sales_pipeline_analytics"("org_id" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_sales_pipeline_analytics"("org_id" "text") IS 'Fixed conversion rate calculation - now uses cumulative stage progression.
Prospect→Lead: % of total contacts that reached Lead or beyond
Lead→Appointment: % of contacts at Lead+ that reached Appointment or beyond  
Appointment→Presentation: % of contacts with scheduled appointments that reached Presentation';



CREATE OR REPLACE FUNCTION "public"."get_task_status_counts"("org_id" "text") RETURNS "json"
    LANGUAGE "plpgsql" STABLE
    AS $$
DECLARE
  result JSON;
BEGIN
  SELECT json_build_object(
    'totalTasks', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id),
    'pendingTasks', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id AND status = 'pending'),
    'inProgressTasks', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id AND status = 'in_progress'),
    'completedTasks', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id AND status = 'completed'),
    'cancelledTasks', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id AND status = 'cancelled'),
    'scheduledTasks', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id AND status = 'scheduled'),
    'reviewDraftTasks', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id AND task_type = 'review_draft' AND status = 'pending'),
    'meetingTasks', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id AND task_type = 'meeting' AND status = 'pending'),
    'companyVerificationTasks', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id AND task_type = 'company_verification' AND status = 'pending'),
    'meetingsScheduled', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id AND task_type = 'meeting' AND status IN ('pending', 'scheduled')),
    'meetingsCompleted', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id AND task_type = 'meeting' AND status = 'completed'),
    'tasksWithCompany', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id AND company_id IS NOT NULL),
    'tasksWithCampaign', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id AND campaign_id IS NOT NULL),
    'tasksWithContact', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id AND contact_id IS NOT NULL),
    'companyVerificationPending', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id AND task_type = 'company_verification' AND status = 'pending'),
    'companyVerificationCompleted', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id AND task_type = 'company_verification' AND status = 'completed'),
    'overdueTasks', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id AND due_date < NOW() AND status NOT IN ('completed', 'cancelled')),
    'dueTodayTasks', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id AND DATE(due_date) = CURRENT_DATE AND status NOT IN ('completed', 'cancelled')),
    'dueThisWeekTasks', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id AND due_date BETWEEN NOW() AND NOW() + INTERVAL '7 days' AND status NOT IN ('completed', 'cancelled')),
    'createdToday', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id AND DATE(created_at) = CURRENT_DATE),
    'completedToday', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id AND DATE(completed_at) = CURRENT_DATE),
    'urgentPriorityTasks', 0,
    'highPriorityTasks', 0,
    'normalPriorityTasks', 0,
    'lowPriorityTasks', 0
  ) INTO result;

  RETURN result;
END;
$$;


ALTER FUNCTION "public"."get_task_status_counts"("org_id" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_task_status_counts"("org_id" "text") IS 'Task statistics function using only valid task types';



CREATE OR REPLACE FUNCTION "public"."get_token_usage_by_date_range"("p_organization_id" "text", "p_start_date" timestamp with time zone, "p_end_date" timestamp with time zone, "p_provider" "text" DEFAULT NULL::"text") RETURNS TABLE("provider" "text", "model_name" "text", "total_calls" bigint, "total_tokens" bigint, "total_input_tokens" bigint, "total_output_tokens" bigint)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        tu.provider,
        tu.model_name,
        SUM(tu.total_calls)::BIGINT as total_calls,
        SUM(tu.total_tokens)::BIGINT as total_tokens,
        SUM(tu.total_input_tokens)::BIGINT as total_input_tokens,
        SUM(tu.total_output_tokens)::BIGINT as total_output_tokens
    FROM token_usage tu
    WHERE tu.organization_id = p_organization_id
        AND tu.tracking_start >= p_start_date
        AND tu.tracking_end <= p_end_date
        AND (p_provider IS NULL OR tu.provider = p_provider)
    GROUP BY tu.provider, tu.model_name
    ORDER BY tu.provider, tu.model_name;
END;
$$;


ALTER FUNCTION "public"."get_token_usage_by_date_range"("p_organization_id" "text", "p_start_date" timestamp with time zone, "p_end_date" timestamp with time zone, "p_provider" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_token_usage_stats"("p_organization_id" "text", "p_start_date" "date", "p_end_date" "date", "p_model_name" "text" DEFAULT NULL::"text", "p_campaign_id" "text" DEFAULT NULL::"text") RETURNS TABLE("total_input_tokens" bigint, "total_output_tokens" bigint, "total_tokens" bigint, "total_processing_time" numeric, "total_runs" bigint, "total_api_calls" bigint)
    LANGUAGE "plpgsql" STABLE
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COALESCE(SUM(u.input_tokens), 0)::BIGINT AS total_input_tokens,
        COALESCE(SUM(u.output_tokens), 0)::BIGINT AS total_output_tokens,
        COALESCE(SUM(u.total_tokens), 0)::BIGINT AS total_tokens,
        0::NUMERIC AS total_processing_time,
        COALESCE(SUM(u.api_calls), 0)::BIGINT AS total_runs,
        COALESCE(SUM(u.api_calls), 0)::BIGINT AS total_api_calls
    FROM usage u
    WHERE u.organization_id = p_organization_id
      AND DATE(u.created_at AT TIME ZONE 'UTC') >= p_start_date
      AND DATE(u.created_at AT TIME ZONE 'UTC') <= p_end_date
      AND (p_model_name IS NULL OR u.model_name = p_model_name)
      AND (p_campaign_id IS NULL OR u.campaign_id = p_campaign_id);
END;
$$;


ALTER FUNCTION "public"."get_token_usage_stats"("p_organization_id" "text", "p_start_date" "date", "p_end_date" "date", "p_model_name" "text", "p_campaign_id" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_token_usage_stats"("p_organization_id" "text", "p_start_date" "date", "p_end_date" "date", "p_model_name" "text", "p_campaign_id" "text") IS 'Returns aggregated token usage stats for an organization with proper UTC date handling';



CREATE OR REPLACE FUNCTION "public"."get_token_usage_summary"("p_organization_id" "text", "p_start_date" "date", "p_end_date" "date", "p_model_name" "text" DEFAULT NULL::"text", "p_campaign_id" "text" DEFAULT NULL::"text") RETURNS TABLE("period_start" timestamp with time zone, "total_input_tokens" bigint, "total_output_tokens" bigint, "total_tokens" bigint, "total_runs" bigint, "total_api_calls" bigint, "provider" "text", "model_name" "text", "unique_sessions" bigint)
    LANGUAGE "plpgsql" STABLE
    AS $$
BEGIN
    RETURN QUERY
    WITH date_series AS (
        -- Generate all dates in the range
        SELECT generate_series(
            p_start_date::timestamp AT TIME ZONE 'UTC',
            p_end_date::timestamp AT TIME ZONE 'UTC',
            '1 day'::interval
        )::date AS usage_date
    ),
    daily_usage AS (
        -- Aggregate usage data by date (using DATE to extract UTC date)
        SELECT 
            DATE(u.created_at AT TIME ZONE 'UTC') AS usage_date,
            SUM(COALESCE(u.input_tokens, 0))::BIGINT AS total_input_tokens,
            SUM(COALESCE(u.output_tokens, 0))::BIGINT AS total_output_tokens,
            SUM(COALESCE(u.total_tokens, 0))::BIGINT AS total_tokens,
            SUM(COALESCE(u.api_calls, 0))::BIGINT AS total_runs,
            SUM(COALESCE(u.api_calls, 0))::BIGINT AS total_api_calls,
            STRING_AGG(DISTINCT u.provider, ', ') AS provider,
            STRING_AGG(DISTINCT u.model_name, ', ') AS model_name,
            COUNT(DISTINCT u.session_id)::BIGINT AS unique_sessions
        FROM usage u
        WHERE u.organization_id = p_organization_id
          AND DATE(u.created_at AT TIME ZONE 'UTC') >= p_start_date
          AND DATE(u.created_at AT TIME ZONE 'UTC') <= p_end_date
          AND (p_model_name IS NULL OR u.model_name = p_model_name)
          AND (p_campaign_id IS NULL OR u.campaign_id = p_campaign_id)
        GROUP BY DATE(u.created_at AT TIME ZONE 'UTC')
    )
    SELECT 
        (ds.usage_date || 'T00:00:00Z')::timestamp with time zone AS period_start,
        COALESCE(du.total_input_tokens, 0)::BIGINT,
        COALESCE(du.total_output_tokens, 0)::BIGINT,
        COALESCE(du.total_tokens, 0)::BIGINT,
        COALESCE(du.total_runs, 0)::BIGINT,
        COALESCE(du.total_api_calls, 0)::BIGINT,
        COALESCE(du.provider, '')::TEXT,
        COALESCE(du.model_name, '')::TEXT,
        COALESCE(du.unique_sessions, 0)::BIGINT
    FROM date_series ds
    LEFT JOIN daily_usage du ON ds.usage_date = du.usage_date
    ORDER BY ds.usage_date;
END;
$$;


ALTER FUNCTION "public"."get_token_usage_summary"("p_organization_id" "text", "p_start_date" "date", "p_end_date" "date", "p_model_name" "text", "p_campaign_id" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_token_usage_summary"("p_organization_id" "text", "p_start_date" "date", "p_end_date" "date", "p_model_name" "text", "p_campaign_id" "text") IS 'Returns daily token usage summary for an organization with proper UTC date handling';



CREATE OR REPLACE FUNCTION "public"."get_unified_token_usage_by_date_range"("p_organization_id" "text", "p_start_date" timestamp with time zone, "p_end_date" timestamp with time zone, "p_provider" "text" DEFAULT NULL::"text") RETURNS TABLE("provider" "text", "model_name" "text", "total_runs" bigint, "total_calls" bigint, "total_tokens" bigint, "total_input_tokens" bigint, "total_output_tokens" bigint)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        ar.provider,
        ar.model_name,
        COUNT(*) FILTER (WHERE ar.provider = 'agent_run')::BIGINT as total_runs,
        SUM(ar.total_calls)::BIGINT as total_calls,
        SUM(ar.total_tokens)::BIGINT as total_tokens,
        SUM(ar.total_input_tokens)::BIGINT as total_input_tokens,
        SUM(ar.total_output_tokens)::BIGINT as total_output_tokens
    FROM agent_runs ar
    WHERE ar.organization_id = p_organization_id
        AND ar.tracking_start >= p_start_date
        AND ar.tracking_end <= p_end_date
        AND (p_provider IS NULL OR ar.provider = p_provider)
    GROUP BY ar.provider, ar.model_name
    ORDER BY ar.provider, ar.model_name;
END;
$$;


ALTER FUNCTION "public"."get_unified_token_usage_by_date_range"("p_organization_id" "text", "p_start_date" timestamp with time zone, "p_end_date" timestamp with time zone, "p_provider" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_unified_token_usage_by_date_range"("p_organization_id" "text", "p_start_date" timestamp with time zone, "p_end_date" timestamp with time zone, "p_provider" "text") IS 'Get unified usage statistics from agent_runs table by date range';



CREATE OR REPLACE FUNCTION "public"."get_unused_companies_for_outreach"("p_organization_id" "text", "p_limit" integer DEFAULT 100) RETURNS TABLE("id" "uuid", "name" "text", "domain" "text", "linkedin_url" "text", "industry" "text", "city" "text", "country" "text", "created_at" timestamp with time zone)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        c.id,
        c.name,
        c.domain,
        c.linkedin_url,
        c.industry,
        c.city,
        c.country,
        c.created_at
    FROM companies c
    WHERE c.organization_id = p_organization_id
    AND (c.used_for_outreach = FALSE OR c.used_for_outreach IS NULL)
    ORDER BY c.created_at DESC
    LIMIT p_limit;
END;
$$;


ALTER FUNCTION "public"."get_unused_companies_for_outreach"("p_organization_id" "text", "p_limit" integer) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_unused_companies_for_outreach"("p_organization_id" "text", "p_limit" integer) IS 'Returns companies that have not been used for outreach';



CREATE OR REPLACE FUNCTION "public"."get_usage_by_date_range"("p_organization_id" "text", "p_start_date" "date", "p_end_date" "date", "p_provider" "text" DEFAULT NULL::"text") RETURNS TABLE("provider" "text", "model_name" "text", "total_api_calls" bigint, "total_input_tokens" bigint, "total_output_tokens" bigint, "total_tokens" bigint, "unique_sessions" bigint)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        u.provider,
        u.model_name,
        SUM(u.api_calls)::BIGINT as total_api_calls,
        SUM(u.input_tokens)::BIGINT as total_input_tokens,
        SUM(u.output_tokens)::BIGINT as total_output_tokens,
        SUM(u.total_tokens)::BIGINT as total_tokens,
        COUNT(DISTINCT u.session_id)::BIGINT as unique_sessions
    FROM usage u
    WHERE u.organization_id = p_organization_id
        AND DATE(u.created_at) >= p_start_date
        AND DATE(u.created_at) <= p_end_date
        AND (p_provider IS NULL OR u.provider = p_provider)
    GROUP BY u.provider, u.model_name
    ORDER BY u.provider, u.model_name;
END;
$$;


ALTER FUNCTION "public"."get_usage_by_date_range"("p_organization_id" "text", "p_start_date" "date", "p_end_date" "date", "p_provider" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."log_file_upload"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  -- Simple logging instead of HTTP call
  RAISE NOTICE 'File uploaded: % by %', NEW.file_name, NEW.uploaded_by;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."log_file_upload"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."log_file_upload"() IS 'Logs file uploads instead of making HTTP calls to avoid net extension dependency';



CREATE OR REPLACE FUNCTION "public"."mark_companies_for_outreach"("p_organization_id" "text", "p_campaign_id" "uuid", "p_campaign_name" "text", "p_company_identifiers" "jsonb") RETURNS TABLE("company_id" "uuid", "company_name" "text", "was_already_used" boolean, "marked_successfully" boolean)
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    company_record RECORD;
    company_identifier JSONB;
    current_timestamp TIMESTAMPTZ := NOW();
BEGIN
    -- Loop through each company identifier
    FOR company_identifier IN SELECT * FROM jsonb_array_elements(p_company_identifiers)
    LOOP
        -- Try to find the company by LinkedIn URL first (most reliable)
        IF company_identifier->>'linkedin_url' IS NOT NULL AND company_identifier->>'linkedin_url' != '' THEN
            SELECT * INTO company_record
            FROM companies 
            WHERE organization_id = p_organization_id 
            AND linkedin_url = company_identifier->>'linkedin_url';
        END IF;
        
        -- If not found by LinkedIn URL, try by name
        IF NOT FOUND AND company_identifier->>'name' IS NOT NULL AND company_identifier->>'name' != '' THEN
            SELECT * INTO company_record
            FROM companies 
            WHERE organization_id = p_organization_id 
            AND LOWER(name) = LOWER(company_identifier->>'name');
        END IF;
        
        -- If not found by name, try by domain
        IF NOT FOUND AND company_identifier->>'domain' IS NOT NULL AND company_identifier->>'domain' != '' THEN
            SELECT * INTO company_record
            FROM companies 
            WHERE organization_id = p_organization_id 
            AND domain = company_identifier->>'domain';
        END IF;
        
        -- If company exists, update outreach tracking
        IF FOUND THEN
            UPDATE companies 
            SET 
                used_for_outreach = TRUE,
                first_outreach_date = COALESCE(first_outreach_date, current_timestamp),
                last_outreach_date = current_timestamp,
                outreach_count = outreach_count + 1,
                outreach_campaigns = CASE 
                    WHEN p_campaign_name = ANY(outreach_campaigns) THEN outreach_campaigns
                    ELSE array_append(outreach_campaigns, p_campaign_name)
                END,
                updated_at = current_timestamp
            WHERE id = company_record.id;
            
            RETURN QUERY SELECT 
                company_record.id,
                company_record.name,
                company_record.used_for_outreach AS was_already_used,
                TRUE AS marked_successfully;
        ELSE
            -- Company not found in database, create a new record
            INSERT INTO companies (
                organization_id,
                name,
                domain,
                linkedin_url,
                used_for_outreach,
                first_outreach_date,
                last_outreach_date,
                outreach_count,
                outreach_campaigns,
                created_at,
                updated_at
            ) VALUES (
                p_organization_id,
                COALESCE(company_identifier->>'name', 'Unknown Company'),
                company_identifier->>'domain',
                company_identifier->>'linkedin_url',
                TRUE,
                current_timestamp,
                current_timestamp,
                1,
                ARRAY[p_campaign_name],
                current_timestamp,
                current_timestamp
            ) RETURNING id, name INTO company_record;
            
            RETURN QUERY SELECT 
                company_record.id,
                company_record.name,
                FALSE AS was_already_used,
                TRUE AS marked_successfully;
        END IF;
    END LOOP;
END;
$$;


ALTER FUNCTION "public"."mark_companies_for_outreach"("p_organization_id" "text", "p_campaign_id" "uuid", "p_campaign_name" "text", "p_company_identifiers" "jsonb") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."mark_companies_for_outreach"("p_organization_id" "text", "p_campaign_id" "uuid", "p_campaign_name" "text", "p_company_identifiers" "jsonb") IS 'Marks companies as used for outreach and tracks campaign usage';



CREATE OR REPLACE FUNCTION "public"."remove_deleted_file_from_companies"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  -- Only update rows that actually contain the file id
  UPDATE companies
     SET useful_case_file_ids = array_remove(COALESCE(useful_case_file_ids, '{}'::uuid[]), OLD.id),
         updated_at = NOW()
   WHERE OLD.id = ANY(COALESCE(useful_case_file_ids, '{}'::uuid[]))
     AND (organization_id = OLD.organization_id OR organization_id IS NOT DISTINCT FROM OLD.organization_id);

  RETURN NULL; -- AFTER DELETE trigger does not modify the deleted row
END;
$$;


ALTER FUNCTION "public"."remove_deleted_file_from_companies"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."reset_icp_blocking_for_profile"("profile_id" "uuid") RETURNS integer
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    updated_count INTEGER;
BEGIN
    UPDATE campaign_companies
    SET 
        blocked_by_icp = FALSE,
        icp_blocked_at = NULL,
        icp_failed_filters = '[]'::jsonb,
        icp_score_when_blocked = NULL,
        updated_at = NOW()
    WHERE icp_profile_id_used = profile_id
      AND blocked_by_icp = TRUE;
    
    GET DIAGNOSTICS updated_count = ROW_COUNT;
    RETURN updated_count;
END;
$$;


ALTER FUNCTION "public"."reset_icp_blocking_for_profile"("profile_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."reset_icp_blocking_for_profile"("profile_id" "uuid") IS 'Resets ICP blocking status for all companies that were blocked using a specific ICP profile. Use this when an ICP profile is updated to allow reprocessing.';



CREATE OR REPLACE FUNCTION "public"."set_task_priority_rank"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.priority_rank := CASE NEW.priority
        WHEN 'urgent' THEN 1
        WHEN 'high' THEN 2
        WHEN 'normal' THEN 3
        WHEN 'low' THEN 4
        ELSE 3
    END;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."set_task_priority_rank"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_campaign_companies_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_campaign_companies_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_campaign_total_companies"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    -- Update total_companies for the affected campaign
    UPDATE campaigns 
    SET total_contacts = (
        SELECT COUNT(*) 
        FROM campaign_companies 
        WHERE campaign_id = COALESCE(NEW.campaign_id, OLD.campaign_id)
        AND status = 'active'
    )
    WHERE id = COALESCE(NEW.campaign_id, OLD.campaign_id);
    
    RETURN COALESCE(NEW, OLD);
END;
$$;


ALTER FUNCTION "public"."update_campaign_total_companies"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_company_blocked_status"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    -- Check if icp_score indicates blocking
    IF NEW.icp_score IS NOT NULL THEN
        IF (NEW.icp_score->>'blocked')::boolean = TRUE OR 
           (NEW.icp_score->'llm_analysis'->>'blocked')::boolean = TRUE THEN
            NEW.blocked_by_icp := TRUE;
        ELSE
            NEW.blocked_by_icp := FALSE;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_company_blocked_status"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_company_contacts_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_company_contacts_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_deep_research_settings_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_deep_research_settings_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_organization_settings_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_organization_settings_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_selected_company_ids"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $_$
BEGIN
    -- Extract selected company IDs from curated_companies JSONB
    IF NEW.curated_companies IS NOT NULL THEN
        NEW.selected_company_ids := ARRAY(
            SELECT jsonb_array_elements_text(
                jsonb_path_query_array(NEW.curated_companies, '$[*] ? (@.selected == true).id')
            )
        );
    END IF;
    
    RETURN NEW;
END;
$_$;


ALTER FUNCTION "public"."update_selected_company_ids"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_system_config_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_system_config_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_updated_at_column"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_updated_at_column"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_usage_summary"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    INSERT INTO usage_summary (
        organization_id,
        provider,
        model_name,
        date,
        total_api_calls,
        total_input_tokens,
        total_output_tokens,
        total_tokens,
        unique_sessions
    ) VALUES (
        NEW.organization_id,
        NEW.provider,
        NEW.model_name,
        DATE(NEW.created_at),
        NEW.api_calls,
        NEW.input_tokens,
        NEW.output_tokens,
        NEW.total_tokens,
        1  -- This will be recalculated in the conflict resolution
    )
    ON CONFLICT (organization_id, provider, model_name, date)
    DO UPDATE SET
        total_api_calls = usage_summary.total_api_calls + NEW.api_calls,
        total_input_tokens = usage_summary.total_input_tokens + NEW.input_tokens,
        total_output_tokens = usage_summary.total_output_tokens + NEW.output_tokens,
        total_tokens = usage_summary.total_tokens + NEW.total_tokens,
        unique_sessions = (
            SELECT COUNT(DISTINCT session_id) 
            FROM usage 
            WHERE organization_id = NEW.organization_id 
            AND provider = NEW.provider 
            AND COALESCE(model_name, '') = COALESCE(NEW.model_name, '')
            AND DATE(created_at) = DATE(NEW.created_at)
        ),
        updated_at = NOW();
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_usage_summary"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."style_guidelines" (
    "id" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()),
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()),
    "organization_id" "text" NOT NULL,
    "brand_voice" "text",
    "tone_attributes" "text"[],
    "key_phrases" "text"[],
    "avoid_phrases" "text"[],
    "writing_style" "text",
    "target_audience" "text",
    "tone_of_voice_sound" "text",
    "tone_of_voice_emotions" "text"[],
    "tone_of_voice_personality_traits" "text"[],
    "key_word_choices_lexical_fields" "jsonb" DEFAULT '{}'::"jsonb",
    "key_word_choices_dictionary" "jsonb" DEFAULT '[]'::"jsonb",
    "writing_style_formality" "text",
    "writing_style_sentence_voice" "text"
);


ALTER TABLE "public"."style_guidelines" OWNER TO "postgres";


COMMENT ON TABLE "public"."style_guidelines" IS 'Simplified brand writing guidelines for AI-powered content generation';



COMMENT ON COLUMN "public"."style_guidelines"."brand_voice" IS 'Overall brand voice description (e.g., Professional yet approachable)';



COMMENT ON COLUMN "public"."style_guidelines"."tone_attributes" IS 'Key attributes describing brand tone (e.g., confident, empathetic, innovative)';



COMMENT ON COLUMN "public"."style_guidelines"."key_phrases" IS 'Important words and phrases to use in content';



COMMENT ON COLUMN "public"."style_guidelines"."avoid_phrases" IS 'Words and phrases to avoid in communications';



COMMENT ON COLUMN "public"."style_guidelines"."writing_style" IS 'General writing style description';



COMMENT ON COLUMN "public"."style_guidelines"."target_audience" IS 'Description of target audience';



CREATE OR REPLACE FUNCTION "public"."upsert_style_guidelines"("p_organization_id" "text", "p_brand_voice" "text" DEFAULT NULL::"text", "p_tone_attributes" "text"[] DEFAULT NULL::"text"[], "p_key_phrases" "text"[] DEFAULT NULL::"text"[], "p_avoid_phrases" "text"[] DEFAULT NULL::"text"[], "p_writing_style" "text" DEFAULT NULL::"text", "p_target_audience" "text" DEFAULT NULL::"text") RETURNS "public"."style_guidelines"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_result style_guidelines;
BEGIN
    INSERT INTO style_guidelines (
        organization_id,
        brand_voice,
        tone_attributes,
        key_phrases,
        avoid_phrases,
        writing_style,
        target_audience,
        -- Auto-populate backward compatibility fields
        tone_of_voice_sound,
        tone_of_voice_emotions,
        tone_of_voice_personality_traits,
        key_word_choices_lexical_fields,
        key_word_choices_dictionary,
        writing_style_formality,
        writing_style_sentence_voice
    ) VALUES (
        p_organization_id,
        p_brand_voice,
        p_tone_attributes,
        p_key_phrases,
        p_avoid_phrases,
        p_writing_style,
        p_target_audience,
        -- Backward compatibility mappings
        p_brand_voice,
        COALESCE(p_tone_attributes[1:array_length(p_tone_attributes, 1)/2], '{}'),
        COALESCE(p_tone_attributes[array_length(p_tone_attributes, 1)/2+1:], '{}'),
        jsonb_build_object(
            'brand_identity', to_jsonb(COALESCE(p_key_phrases[1:3], '{}')),
            'communication_style', to_jsonb(COALESCE(p_key_phrases[4:6], '{}')),
            'value_proposition', to_jsonb(COALESCE(p_key_phrases[7:], '{}'))
        ),
        CASE 
            WHEN p_avoid_phrases IS NOT NULL AND array_length(p_avoid_phrases, 1) > 0 THEN
                (SELECT jsonb_agg(
                    jsonb_build_object(
                        'term', phrase,
                        'category', 'avoid',
                        'example', 'Do not use "' || phrase || '" in communications'
                    )
                ) FROM unnest(p_avoid_phrases) AS phrase)
            ELSE '[]'::jsonb
        END,
        CASE 
            WHEN p_writing_style ILIKE '%formal%' THEN 'formal'
            WHEN p_writing_style ILIKE '%casual%' THEN 'casual'
            ELSE 'professional'
        END,
        CASE 
            WHEN p_writing_style ILIKE '%active%' THEN 'active'
            WHEN p_writing_style ILIKE '%passive%' THEN 'passive'
            ELSE 'balanced'
        END
    )
    ON CONFLICT (organization_id) 
    DO UPDATE SET
        brand_voice = EXCLUDED.brand_voice,
        tone_attributes = EXCLUDED.tone_attributes,
        key_phrases = EXCLUDED.key_phrases,
        avoid_phrases = EXCLUDED.avoid_phrases,
        writing_style = EXCLUDED.writing_style,
        target_audience = EXCLUDED.target_audience,
        tone_of_voice_sound = EXCLUDED.tone_of_voice_sound,
        tone_of_voice_emotions = EXCLUDED.tone_of_voice_emotions,
        tone_of_voice_personality_traits = EXCLUDED.tone_of_voice_personality_traits,
        key_word_choices_lexical_fields = EXCLUDED.key_word_choices_lexical_fields,
        key_word_choices_dictionary = EXCLUDED.key_word_choices_dictionary,
        writing_style_formality = EXCLUDED.writing_style_formality,
        writing_style_sentence_voice = EXCLUDED.writing_style_sentence_voice,
        updated_at = TIMEZONE('utc', NOW())
    RETURNING * INTO v_result;
    
    RETURN v_result;
END;
$$;


ALTER FUNCTION "public"."upsert_style_guidelines"("p_organization_id" "text", "p_brand_voice" "text", "p_tone_attributes" "text"[], "p_key_phrases" "text"[], "p_avoid_phrases" "text"[], "p_writing_style" "text", "p_target_audience" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_task_contact"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    -- Validate that contact belongs to the same organization
    IF NEW.contact_id IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM contacts 
            WHERE id = NEW.contact_id 
            AND organization_id = NEW.organization_id
        ) THEN
            RAISE EXCEPTION 'Contact does not belong to the same organization';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_task_contact"() OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."campaign_activities" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "campaign_id" "uuid" NOT NULL,
    "contact_id" "uuid",
    "organization_id" "text" NOT NULL,
    "user_id" "text",
    "activity_type" "text" NOT NULL,
    "activity_data" "jsonb" DEFAULT '{}'::"jsonb",
    "occurred_at" timestamp with time zone DEFAULT "now"(),
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."campaign_activities" OWNER TO "postgres";


COMMENT ON TABLE "public"."campaign_activities" IS 'Detailed activity log for all campaign-related events';



COMMENT ON COLUMN "public"."campaign_activities"."activity_data" IS 'Additional data specific to the activity type';



CREATE TABLE IF NOT EXISTS "public"."campaign_companies" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "campaign_id" "uuid" NOT NULL,
    "company_id" "uuid" NOT NULL,
    "organization_id" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "blocked_by_icp" boolean DEFAULT false,
    "icp_profile_id_used" "uuid",
    "icp_blocked_at" timestamp with time zone,
    "icp_failed_filters" "jsonb" DEFAULT '[]'::"jsonb",
    "icp_score_when_blocked" numeric(5,2)
);


ALTER TABLE "public"."campaign_companies" OWNER TO "postgres";


COMMENT ON COLUMN "public"."campaign_companies"."blocked_by_icp" IS 'Whether this company was blocked by ICP hard filters';



COMMENT ON COLUMN "public"."campaign_companies"."icp_profile_id_used" IS 'The ICP profile ID that was used when this company was scored/blocked';



COMMENT ON COLUMN "public"."campaign_companies"."icp_blocked_at" IS 'Timestamp when company was blocked by ICP filters';



COMMENT ON COLUMN "public"."campaign_companies"."icp_failed_filters" IS 'Array of failed hard filter reasons when blocked';



COMMENT ON COLUMN "public"."campaign_companies"."icp_score_when_blocked" IS 'ICP score at time of blocking (usually 0 for hard filter failures)';



CREATE TABLE IF NOT EXISTS "public"."campaign_emails" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "campaign_id" "uuid" NOT NULL,
    "contact_id" "uuid" NOT NULL,
    "organization_id" "text" NOT NULL,
    "status" "public"."email_status" DEFAULT 'draft'::"public"."email_status",
    "subject" "text",
    "content" "text",
    "message_id" "text",
    "thread_id" "text",
    "sent_at" timestamp with time zone,
    "delivered_at" timestamp with time zone,
    "opened_at" timestamp with time zone,
    "first_opened_at" timestamp with time zone,
    "clicked_at" timestamp with time zone,
    "replied_at" timestamp with time zone,
    "bounced_at" timestamp with time zone,
    "reply_content" "text",
    "reply_received_at" timestamp with time zone,
    "open_count" integer DEFAULT 0,
    "click_count" integer DEFAULT 0,
    "error_message" "text",
    "error_code" "text",
    "metadata" "jsonb" DEFAULT '{}'::"jsonb",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "approved_at" timestamp with time zone,
    "approved_by_user_id" "text",
    CONSTRAINT "campaign_emails_valid_refs" CHECK ((("campaign_id" IS NOT NULL) AND ("contact_id" IS NOT NULL)))
);


ALTER TABLE "public"."campaign_emails" OWNER TO "postgres";


COMMENT ON TABLE "public"."campaign_emails" IS 'Tracks individual emails sent as part of campaigns';



COMMENT ON COLUMN "public"."campaign_emails"."thread_id" IS 'Email thread ID for tracking conversations (e.g., Gmail thread ID)';



COMMENT ON COLUMN "public"."campaign_emails"."approved_at" IS 'Timestamp when the email was approved by a user (before actual sending)';



COMMENT ON COLUMN "public"."campaign_emails"."approved_by_user_id" IS 'User ID of the person who approved the email';



CREATE TABLE IF NOT EXISTS "public"."campaign_files" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "campaign_id" "uuid" NOT NULL,
    "file_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "file_name" "text",
    "file_type" "text",
    "file_url" "text",
    "file_size" integer,
    "file_category" "text",
    "uploaded_by" "text",
    "uploaded_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "campaign_files_file_or_metadata_check" CHECK ((("file_id" IS NOT NULL) OR (("file_name" IS NOT NULL) AND ("file_type" IS NOT NULL) AND ("file_url" IS NOT NULL) AND ("file_size" IS NOT NULL))))
);


ALTER TABLE "public"."campaign_files" OWNER TO "postgres";


COMMENT ON TABLE "public"."campaign_files" IS 'Stores campaign-specific files. Can either reference organization_files (general knowledge base) via file_id, or store campaign-specific files directly with metadata. Campaign-specific files are NOT included in the general knowledge base.';



COMMENT ON COLUMN "public"."campaign_files"."campaign_id" IS 'Reference to the campaign that uses this document';



COMMENT ON COLUMN "public"."campaign_files"."file_id" IS 'Reference to organization_file (if file is from general knowledge base). NULL for campaign-specific files.';



CREATE TABLE IF NOT EXISTS "public"."campaign_seed_companies" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "campaign_id" "uuid" NOT NULL,
    "organization_id" "text" NOT NULL,
    "seed_company_url" "text" NOT NULL,
    "seed_company_name" "text",
    "seed_company_id" "text",
    "current_page" integer DEFAULT 0 NOT NULL,
    "total_pages_found" integer,
    "total_elements_found" integer,
    "is_active" boolean DEFAULT false NOT NULL,
    "is_completed" boolean DEFAULT false NOT NULL,
    "processing_order" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."campaign_seed_companies" OWNER TO "postgres";


COMMENT ON TABLE "public"."campaign_seed_companies" IS 'Tracks seed companies used for lookalike discovery and their pagination state';



COMMENT ON COLUMN "public"."campaign_seed_companies"."seed_company_url" IS 'LinkedIn URL of the seed company used for lookalike discovery';



COMMENT ON COLUMN "public"."campaign_seed_companies"."current_page" IS 'Current page number being processed (0-indexed)';



COMMENT ON COLUMN "public"."campaign_seed_companies"."total_pages_found" IS 'Total number of pages available for this seed company';



COMMENT ON COLUMN "public"."campaign_seed_companies"."total_elements_found" IS 'Total number of companies found for this seed company';



COMMENT ON COLUMN "public"."campaign_seed_companies"."is_active" IS 'Indicates which seed company is currently being processed';



COMMENT ON COLUMN "public"."campaign_seed_companies"."is_completed" IS 'Indicates whether all pages have been processed for this seed company';



COMMENT ON COLUMN "public"."campaign_seed_companies"."processing_order" IS 'Order in which seed companies should be processed (0 = first, 1 = second, etc.)';



CREATE TABLE IF NOT EXISTS "public"."campaigns" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "text" NOT NULL,
    "user_id" "text" NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "campaign_type" "text" DEFAULT 'email'::"text",
    "status" "public"."campaign_status" DEFAULT 'draft'::"public"."campaign_status",
    "target_audience" "jsonb" DEFAULT '{}'::"jsonb",
    "settings" "jsonb" DEFAULT '{}'::"jsonb",
    "tags" "text"[] DEFAULT '{}'::"text"[],
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "started_at" timestamp with time zone,
    "completed_at" timestamp with time zone,
    "wizard_completed" boolean DEFAULT false,
    "icp_min_employees" integer,
    "icp_max_employees" integer,
    "icp_sales_process" "text"[] DEFAULT '{}'::"text"[],
    "icp_industries" "text"[] DEFAULT '{}'::"text"[],
    "icp_job_titles" "text"[] DEFAULT '{}'::"text"[],
    "icp_primary_regions" "text"[] DEFAULT '{}'::"text"[],
    "icp_secondary_regions" "text"[] DEFAULT '{}'::"text"[],
    "icp_focus_areas" "text"[] DEFAULT '{}'::"text"[],
    "icp_pain_points" "text"[] DEFAULT '{}'::"text"[],
    "icp_keywords" "text"[] DEFAULT '{}'::"text"[],
    "b2b_results" "jsonb",
    "csv_results" "jsonb",
    "product_description" "text",
    "lead_source" "text",
    "launched_at" timestamp with time zone,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb",
    "curated_companies" "jsonb",
    "selected_company_ids" "text"[] DEFAULT '{}'::"text"[],
    "total_companies" integer DEFAULT 0,
    "b2b_search_filters" "jsonb" DEFAULT '{}'::"jsonb",
    "b2b_search_page_size" integer,
    "b2b_search_last_page" integer,
    "b2b_search_total_pages" integer,
    "b2b_search_total_elements" integer,
    "estimated_total_companies" integer,
    "csv_processed_index" "text"[] DEFAULT '{}'::"text"[],
    "language" "text" DEFAULT 'en'::"text" NOT NULL,
    "deep_research_provider" "text",
    "deep_research_types" "text"[] DEFAULT '{}'::"text"[],
    "deep_research_override" boolean DEFAULT false,
    "icp_profile_id" "uuid",
    "workflow" "jsonb",
    "current_workflow_node_id" "uuid",
    "csv_template_upload" boolean DEFAULT false NOT NULL,
    "lookalike_total_found" integer DEFAULT 0,
    "lookalike_total_processed" integer DEFAULT 0,
    "lookalike_last_page" integer DEFAULT 0,
    "lookalike_total_pages" integer,
    "autopilot_enabled" boolean DEFAULT false NOT NULL,
    "autopilot_company_verification" boolean DEFAULT true NOT NULL,
    "autopilot_email_review" boolean DEFAULT true NOT NULL,
    "autopilot_min_icp_score" integer DEFAULT 70,
    "autopilot_auto_decline_below_min_icp_score" boolean DEFAULT true NOT NULL,
    "autopilot_auto_confirm_initial_emails" boolean DEFAULT true NOT NULL,
    "autopilot_auto_confirm_followup_emails" boolean DEFAULT true NOT NULL,
    "autopilot_auto_confirm_reply_emails" boolean DEFAULT false NOT NULL,
    "phone_discovery_mode" character varying(50) DEFAULT 'disabled'::character varying,
    "icp_country" "text",
    "icp_city" "text",
    "location_type" "text" DEFAULT 'region_based'::"text",
    "email_schedule_hour" integer DEFAULT 8,
    "discover_mobile_numbers" boolean DEFAULT false,
    "icp_locations" "text"[] DEFAULT '{}'::"text"[],
    "company_fetch_limit" integer DEFAULT 300,
    "daily_company_fetch_limit" integer DEFAULT 50,
    "daily_fetch_count" integer DEFAULT 0,
    "daily_fetch_date" "date" DEFAULT CURRENT_DATE,
    "campaign_timezone" "text" DEFAULT 'UTC'::"text",
    CONSTRAINT "autopilot_min_icp_score_range" CHECK ((("autopilot_min_icp_score" IS NULL) OR (("autopilot_min_icp_score" >= 0) AND ("autopilot_min_icp_score" <= 100)))),
    CONSTRAINT "campaigns_location_type_check" CHECK (("location_type" = ANY (ARRAY['region_based'::"text", 'city_based'::"text"]))),
    CONSTRAINT "check_email_schedule_hour" CHECK ((("email_schedule_hour" >= 0) AND ("email_schedule_hour" <= 23)))
);


ALTER TABLE "public"."campaigns" OWNER TO "postgres";


COMMENT ON TABLE "public"."campaigns" IS 'Campaign management table - removed campaign_contacts relationship in favor of campaign_companies relationship (migration 89_20250115)';



COMMENT ON COLUMN "public"."campaigns"."target_audience" IS 'JSON criteria for selecting contacts (e.g., {industry: "tech", size: ">100"})';



COMMENT ON COLUMN "public"."campaigns"."started_at" IS 'Timestamp when the campaign was started (may be same as launched_at or different for paused/resumed campaigns)';



COMMENT ON COLUMN "public"."campaigns"."wizard_completed" IS 'Whether the campaign creation wizard was completed';



COMMENT ON COLUMN "public"."campaigns"."icp_min_employees" IS 'Minimum number of employees for target companies in this campaign';



COMMENT ON COLUMN "public"."campaigns"."icp_max_employees" IS 'Maximum number of employees for target companies in this campaign';



COMMENT ON COLUMN "public"."campaigns"."icp_sales_process" IS 'Sales process characteristics for this campaign';



COMMENT ON COLUMN "public"."campaigns"."icp_industries" IS 'Target industries for this campaign';



COMMENT ON COLUMN "public"."campaigns"."icp_job_titles" IS 'Preferred job titles of prospects for this campaign';



COMMENT ON COLUMN "public"."campaigns"."icp_primary_regions" IS 'Primary geographic regions to target in this campaign';



COMMENT ON COLUMN "public"."campaigns"."icp_secondary_regions" IS 'Secondary geographic regions to target in this campaign';



COMMENT ON COLUMN "public"."campaigns"."icp_focus_areas" IS 'Specific focus areas or niches for this campaign';



COMMENT ON COLUMN "public"."campaigns"."icp_pain_points" IS 'Common pain points of target prospects for this campaign';



COMMENT ON COLUMN "public"."campaigns"."icp_keywords" IS 'Custom keywords/tags for this campaign';



COMMENT ON COLUMN "public"."campaigns"."b2b_results" IS 'Results from B2B enrichment API for manual LinkedIn URL input';



COMMENT ON COLUMN "public"."campaigns"."csv_results" IS 'Results from CSV processing including file info, column mapping, and analysis';



COMMENT ON COLUMN "public"."campaigns"."product_description" IS 'Description of product/service for this campaign';



COMMENT ON COLUMN "public"."campaigns"."lead_source" IS 'Source of leads/companies: csv, manual, ai_generated';



COMMENT ON COLUMN "public"."campaigns"."launched_at" IS 'Timestamp when the campaign was launched/activated for the first time';



COMMENT ON COLUMN "public"."campaigns"."metadata" IS 'Additional metadata for campaigns including external leads, workflow stage, and other campaign-specific data';



COMMENT ON COLUMN "public"."campaigns"."curated_companies" IS 'Array of company data with selection status and curation info';



COMMENT ON COLUMN "public"."campaigns"."selected_company_ids" IS 'Array of selected company IDs for quick filtering and queries';



COMMENT ON COLUMN "public"."campaigns"."total_companies" IS 'Number of companies associated with this campaign';



COMMENT ON COLUMN "public"."campaigns"."b2b_search_filters" IS 'Filters used for B2B search; stored as JSONB';



COMMENT ON COLUMN "public"."campaigns"."b2b_search_page_size" IS 'Page size used in the external B2B search API';



COMMENT ON COLUMN "public"."campaigns"."b2b_search_last_page" IS 'Last page number retrieved from the external B2B search API';



COMMENT ON COLUMN "public"."campaigns"."b2b_search_total_pages" IS 'Total pages as reported by the external B2B search API';



COMMENT ON COLUMN "public"."campaigns"."b2b_search_total_elements" IS 'Total elements as reported by the external B2B search API';



COMMENT ON COLUMN "public"."campaigns"."estimated_total_companies" IS 'Cached estimate of how many companies we expect to find overall for this campaign';



COMMENT ON COLUMN "public"."campaigns"."csv_processed_index" IS 'List of processed CSV row identifiers for this campaign';



COMMENT ON COLUMN "public"."campaigns"."language" IS 'Language code for campaign (en, en-gb, de, fr, sv). Default is en (English).';



COMMENT ON COLUMN "public"."campaigns"."deep_research_provider" IS 'Deep research provider for this campaign: none, exa, perplexity, or both. If null, uses organization default.';



COMMENT ON COLUMN "public"."campaigns"."deep_research_types" IS 'Array of research types to enable: company_overview, funding_history, recent_news, competitive_landscape, growth_signals, icp_analysis. If empty, uses organization default.';



COMMENT ON COLUMN "public"."campaigns"."deep_research_override" IS 'If true, campaign uses its own deep research settings. If false or null, campaign inherits organization-level settings.';



COMMENT ON COLUMN "public"."campaigns"."icp_profile_id" IS 'Link to ICP profile used for this campaign';



COMMENT ON COLUMN "public"."campaigns"."workflow" IS 'JSON structure containing the workflow steps (Email → Wait pattern) with UUIDs for each node';



COMMENT ON COLUMN "public"."campaigns"."current_workflow_node_id" IS 'UUID of the current workflow node being executed for this campaign';



COMMENT ON COLUMN "public"."campaigns"."csv_template_upload" IS 'Indicates whether the campaign uses template CSV format (with First Name, Last Name, etc.) vs regular company-only CSV format';



COMMENT ON COLUMN "public"."campaigns"."lookalike_total_found" IS 'Total number of lookalike companies found based on selected seed companies';



COMMENT ON COLUMN "public"."campaigns"."lookalike_total_processed" IS 'Total number of lookalike companies that have been processed';



COMMENT ON COLUMN "public"."campaigns"."lookalike_last_page" IS 'Last page number of lookalike companies fetched from B2B API';



COMMENT ON COLUMN "public"."campaigns"."lookalike_total_pages" IS 'Total number of pages of lookalike companies available from B2B API';



COMMENT ON COLUMN "public"."campaigns"."autopilot_enabled" IS 'Master switch for autopilot mode - must be true for any auto-approval to work. Default: FALSE';



COMMENT ON COLUMN "public"."campaigns"."autopilot_company_verification" IS 'When true, company verification tasks are automatically approved. Default: TRUE';



COMMENT ON COLUMN "public"."campaigns"."autopilot_email_review" IS 'When true, email review tasks are automatically accepted and sent. Default: TRUE';



COMMENT ON COLUMN "public"."campaigns"."autopilot_min_icp_score" IS 'Minimum ICP score required for auto-approval (0-100). Companies below this score are auto-declined. Default: 70';



COMMENT ON COLUMN "public"."campaigns"."autopilot_auto_decline_below_min_icp_score" IS 'When autopilot + company verification are enabled and a min ICP score is set: if TRUE, companies below min are auto-declined; if FALSE, they remain pending for manual review. Default: TRUE';



COMMENT ON COLUMN "public"."campaigns"."autopilot_auto_confirm_initial_emails" IS 'When true (and autopilot enabled), initial/first outbound email tasks can be auto-accepted/sent. Default: TRUE.';



COMMENT ON COLUMN "public"."campaigns"."autopilot_auto_confirm_followup_emails" IS 'When true (and autopilot enabled), follow-up outbound email tasks can be auto-accepted/sent. Default: TRUE.';



COMMENT ON COLUMN "public"."campaigns"."autopilot_auto_confirm_reply_emails" IS 'When true (and autopilot enabled), reply email tasks can be auto-accepted/sent. Default: FALSE.';



COMMENT ON COLUMN "public"."campaigns"."phone_discovery_mode" IS 'Phone discovery mode: disabled, new_contacts_only (only for future discoveries), or all_contacts (for all contacts in campaign)';



COMMENT ON COLUMN "public"."campaigns"."icp_country" IS 'Country for city-based location targeting';



COMMENT ON COLUMN "public"."campaigns"."icp_city" IS 'City for city-based location targeting';



COMMENT ON COLUMN "public"."campaigns"."location_type" IS 'Location targeting type: region_based or city_based';



COMMENT ON COLUMN "public"."campaigns"."email_schedule_hour" IS 'Hour of day to schedule emails (0-23, where 8 = 8 AM). Used with campaign_timezone to determine local sending time.';



COMMENT ON COLUMN "public"."campaigns"."discover_mobile_numbers" IS 'Whether to discover mobile phone numbers for contacts in this campaign (default: false)';



COMMENT ON COLUMN "public"."campaigns"."company_fetch_limit" IS 'Maximum number of companies that can be fetched/discovered for this campaign. NULL means unlimited.';



COMMENT ON COLUMN "public"."campaigns"."daily_company_fetch_limit" IS 'Maximum number of companies that can be fetched per day for this campaign. NULL means unlimited daily.';



COMMENT ON COLUMN "public"."campaigns"."daily_fetch_count" IS 'Number of companies fetched today. Reset to 0 when daily_fetch_date changes.';



COMMENT ON COLUMN "public"."campaigns"."daily_fetch_date" IS 'The date of the last fetch. Used by the cron job to detect day change and reset daily_fetch_count.';



COMMENT ON COLUMN "public"."campaigns"."campaign_timezone" IS 'Timezone for campaign execution (e.g., UTC, America/New_York). Determines when daily limits reset and when campaigns are triggered.';



CREATE TABLE IF NOT EXISTS "public"."companies" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "text" NOT NULL,
    "name" "text" NOT NULL,
    "website" "text",
    "size" "text",
    "linkedin_url" "text",
    "description" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "used_for_outreach" boolean DEFAULT false,
    "phone" "text",
    "employee_count" integer,
    "logo" "text",
    "location" "text",
    "industries" "text"[],
    "icp_score" "jsonb",
    "deep_research" "jsonb",
    "universal_name" "text",
    "company_type" "text",
    "cover" "text",
    "tagline" "text",
    "founded_year" integer,
    "object_urn" bigint,
    "followers" integer,
    "locations" "jsonb" DEFAULT '{}'::"jsonb",
    "funding_data" "jsonb" DEFAULT '{}'::"jsonb",
    "specialities" "text"[] DEFAULT '{}'::"text"[],
    "hashtags" "text"[] DEFAULT '{}'::"text"[],
    "processing_status" "text" DEFAULT 'pending'::"text",
    "useful_case_file_ids" "uuid"[] DEFAULT '{}'::"uuid"[],
    "outreach_strategy" "jsonb",
    "b2b_result" "jsonb",
    "blocked_by_icp" boolean DEFAULT false,
    "matches_case_study" boolean DEFAULT false,
    "sales_brief" "text",
    "processing_log" "jsonb",
    "deep_research_v2" "jsonb",
    "failure_reason" "text",
    "contact_extraction_status" "text" DEFAULT 'extraction_not_started'::"text",
    CONSTRAINT "companies_processing_status_check" CHECK (("processing_status" = ANY (ARRAY['pending'::"text", 'scheduled'::"text", 'processing'::"text", 'processed'::"text", 'approved'::"text", 'declined'::"text", 'failed'::"text", 'blocked_by_icp'::"text"])))
);


ALTER TABLE "public"."companies" OWNER TO "postgres";


COMMENT ON TABLE "public"."companies" IS 'Company information table. Industry field has been removed as it is not used in the application.';



COMMENT ON COLUMN "public"."companies"."size" IS 'Company size range (e.g., 500-1000, 50-100)';



COMMENT ON COLUMN "public"."companies"."used_for_outreach" IS 'Whether this company has been used for any outreach campaigns';



COMMENT ON COLUMN "public"."companies"."industries" IS 'Array of industries the company operates in';



COMMENT ON COLUMN "public"."companies"."icp_score" IS 'JSONB object containing complete ICP scoring data including total_score, tier, confidence_level, component_scores, reasoning, and recommendations';



COMMENT ON COLUMN "public"."companies"."deep_research" IS 'JSONB object containing complete deep research data including summary, key_insights, icp, growth_signals, recent_news, funding_history, company_profile, competitors, and competitive_landscape';



COMMENT ON COLUMN "public"."companies"."processing_status" IS 'Status of company data processing. Flow: scheduled → processing → processed → (approved OR declined OR blocked_by_icp). Valid values: pending, scheduled, processing, processed, approved, declined, failed, blocked_by_icp';



COMMENT ON COLUMN "public"."companies"."useful_case_file_ids" IS 'List of organization_files IDs that are considered useful case documents for this company.';



COMMENT ON COLUMN "public"."companies"."outreach_strategy" IS 'Outreach strategy configuration and data stored as JSONB including approach methods, messaging preferences, and timing settings';



COMMENT ON COLUMN "public"."companies"."b2b_result" IS 'Stores B2B API response data for the company including enrichment details, contact information, and other structured data from external B2B services';



COMMENT ON COLUMN "public"."companies"."blocked_by_icp" IS 'Whether this company was blocked by ICP hard filters and should not be processed further';



COMMENT ON COLUMN "public"."companies"."matches_case_study" IS 'Whether this company matches reference case studies (used as score modifier, not a signal)';



COMMENT ON COLUMN "public"."companies"."sales_brief" IS 'Sales brief information stored as markdown text. Contains key information about the company for sales purposes. Users can edit this directly.';



COMMENT ON COLUMN "public"."companies"."processing_log" IS 'Detailed log of company processing including B2B enrichment, deep research, ICP scoring, blocking decisions, and LLM outputs. Stored as JSONB for queryability.';



COMMENT ON COLUMN "public"."companies"."deep_research_v2" IS 'Comprehensive deep research results from Perplexity sonar-deep-research model. Contains full research report with citations, search results, and comprehensive analysis of the company including all available details from website, LinkedIn, industry information, etc.';



COMMENT ON COLUMN "public"."companies"."failure_reason" IS 'Stores the reason why a company failed processing. Set when processing_status is changed to failed. Examples: campaign_link_creation_failed, icp_check_failed, enrichment_failed';



COMMENT ON COLUMN "public"."companies"."contact_extraction_status" IS 'Status of contact extraction: extraction_not_started, extracting_contacts, extraction_complete';



CREATE TABLE IF NOT EXISTS "public"."company_activities" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "text" NOT NULL,
    "company_id" "uuid" NOT NULL,
    "contact_id" "uuid",
    "campaign_id" "uuid",
    "task_id" "uuid",
    "activity_type" "public"."company_activity_type" NOT NULL,
    "title" "text" NOT NULL,
    "description" "text",
    "created_by_user_id" "text" NOT NULL,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."company_activities" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."company_contacts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "contact_id" "uuid" NOT NULL,
    "organization_id" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."company_contacts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."contact_activities" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "contact_id" "uuid" NOT NULL,
    "organization_id" "text" NOT NULL,
    "user_id" "text",
    "activity_type" "public"."activity_type" NOT NULL,
    "title" "text" NOT NULL,
    "description" "text",
    "metadata" "jsonb" DEFAULT '{}'::"jsonb",
    "related_to_id" "uuid",
    "related_to_type" "text",
    "occurred_at" timestamp with time zone DEFAULT "now"(),
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."contact_activities" OWNER TO "postgres";


COMMENT ON TABLE "public"."contact_activities" IS 'Stores all activities and interactions with contacts';



COMMENT ON COLUMN "public"."contact_activities"."activity_type" IS 'Type of activity performed';



COMMENT ON COLUMN "public"."contact_activities"."metadata" IS 'Activity-specific data (e.g., email content, call duration)';



CREATE TABLE IF NOT EXISTS "public"."contact_channels" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "contact_id" "uuid" NOT NULL,
    "organization_id" "text" NOT NULL,
    "channel_type" "public"."channel_type" NOT NULL,
    "channel_value" "text" NOT NULL,
    "is_primary" boolean DEFAULT false,
    "is_verified" boolean DEFAULT false,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."contact_channels" OWNER TO "postgres";


COMMENT ON TABLE "public"."contact_channels" IS 'Stores communication channels for each contact';



COMMENT ON COLUMN "public"."contact_channels"."channel_type" IS 'Type of communication channel';



COMMENT ON COLUMN "public"."contact_channels"."channel_value" IS 'The actual value (email address, phone number, etc.)';



COMMENT ON COLUMN "public"."contact_channels"."metadata" IS 'Channel-specific metadata (e.g., WhatsApp business account info)';



CREATE TABLE IF NOT EXISTS "public"."contact_notes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "contact_id" "uuid" NOT NULL,
    "organization_id" "text" NOT NULL,
    "user_id" "text",
    "content" "text" NOT NULL,
    "note_type" "text" DEFAULT 'general'::"text",
    "is_pinned" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."contact_notes" OWNER TO "postgres";


COMMENT ON TABLE "public"."contact_notes" IS 'Stores multiple notes for each contact';



COMMENT ON COLUMN "public"."contact_notes"."note_type" IS 'Type of note: general, call, meeting, email, etc.';



COMMENT ON COLUMN "public"."contact_notes"."is_pinned" IS 'Whether this note is pinned to the top';



CREATE TABLE IF NOT EXISTS "public"."contacts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "text" NOT NULL,
    "name" "text" NOT NULL,
    "email" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "linkedin_url" "text",
    "firstname" "text",
    "lastname" "text",
    "headline" "text",
    "summary" "text",
    "location" "jsonb",
    "educations" "jsonb",
    "certifications" "jsonb",
    "languages" "jsonb",
    "skills" "jsonb",
    "analysis" "jsonb",
    "activities" "jsonb",
    "url" "text",
    "identifier" "text",
    "entity_urn" "text",
    "object_urn" bigint,
    "birth_date" "text",
    "picture" "text",
    "background" "text",
    "open_to_work" boolean DEFAULT false,
    "influencer" boolean DEFAULT false,
    "premium" boolean DEFAULT false,
    "industry" "text",
    "organizations" "jsonb" DEFAULT '{}'::"jsonb",
    "patents" "jsonb" DEFAULT '{}'::"jsonb",
    "awards" "jsonb" DEFAULT '{}'::"jsonb",
    "projects" "jsonb" DEFAULT '{}'::"jsonb",
    "publications" "jsonb" DEFAULT '{}'::"jsonb",
    "courses" "jsonb" DEFAULT '{}'::"jsonb",
    "test_scores" "jsonb" DEFAULT '{}'::"jsonb",
    "position_groups" "jsonb" DEFAULT '{}'::"jsonb",
    "volunteer_experiences" "jsonb" DEFAULT '{}'::"jsonb",
    "recommendations" "text"[] DEFAULT '{}'::"text"[],
    "network_info" "jsonb" DEFAULT '{}'::"jsonb",
    "email_validation_response" "jsonb",
    "processing_status" "text" DEFAULT 'pending'::"text",
    "pipeline_stage" "text",
    "ooo_until" timestamp with time zone,
    "unsubscribed_at" timestamp with time zone,
    "stop_drafts" boolean DEFAULT false NOT NULL,
    "last_email_sentiment" "text",
    "last_email_intent" "jsonb",
    "last_thread_id" "text",
    "last_incoming_email_at" timestamp with time zone,
    "stage_updated_at" timestamp with time zone,
    "phone" "text",
    "b2b_email_requested" boolean DEFAULT false,
    "hunter_email_requested" boolean DEFAULT false NOT NULL,
    "hunter_email_response" "jsonb",
    "provider_responses" "jsonb",
    "icypeas_email_requested" boolean DEFAULT false NOT NULL,
    "icypeas_email_response" "jsonb",
    "email_search_status" "text" DEFAULT 'search_not_started'::"text",
    "do_not_contact" boolean DEFAULT false NOT NULL,
    "sales_brief" "text",
    CONSTRAINT "contacts_email_search_status_check" CHECK (("email_search_status" = ANY (ARRAY['search_not_started'::"text", 'started_searching_email'::"text", 'finished_searching_email'::"text"]))),
    CONSTRAINT "contacts_last_email_sentiment_chk" CHECK ((("last_email_sentiment" IS NULL) OR ("last_email_sentiment" = ANY (ARRAY['VERY_POSITIVE'::"text", 'POSITIVE'::"text", 'NEUTRAL'::"text", 'NEGATIVE'::"text", 'VERY_NEGATIVE'::"text"])))),
    CONSTRAINT "contacts_pipeline_stage_chk" CHECK ((("pipeline_stage" IS NULL) OR ("pipeline_stage" = ANY (ARRAY['PROSPECT'::"text", 'LEAD'::"text", 'APPOINTMENT_REQUESTED'::"text", 'APPOINTMENT_SCHEDULED'::"text", 'APPOINTMENT_CANCELLED'::"text", 'PRESENTATION_SCHEDULED'::"text", 'CONTRACT_NEGOTIATIONS'::"text", 'AGREEMENT_IN_PRINCIPLE'::"text", 'CLOSED_WON'::"text", 'CLOSED_LOST'::"text", 'REENGAGEMENT'::"text"]))))
);


ALTER TABLE "public"."contacts" OWNER TO "postgres";


COMMENT ON TABLE "public"."contacts" IS 'Contacts table with cleaned schema matching API response format';



COMMENT ON COLUMN "public"."contacts"."organization_id" IS 'Organization this contact belongs to';



COMMENT ON COLUMN "public"."contacts"."linkedin_url" IS 'LinkedIn profile URL';



COMMENT ON COLUMN "public"."contacts"."firstname" IS 'First name from LinkedIn profile';



COMMENT ON COLUMN "public"."contacts"."lastname" IS 'Last name from LinkedIn profile';



COMMENT ON COLUMN "public"."contacts"."headline" IS 'Professional headline from LinkedIn profile';



COMMENT ON COLUMN "public"."contacts"."summary" IS 'Professional summary from LinkedIn profile';



COMMENT ON COLUMN "public"."contacts"."location" IS 'JSONB object containing location information (country, city, state, etc.)';



COMMENT ON COLUMN "public"."contacts"."educations" IS 'JSONB array of education records';



COMMENT ON COLUMN "public"."contacts"."certifications" IS 'JSONB array of certifications';



COMMENT ON COLUMN "public"."contacts"."languages" IS 'JSONB array of languages';



COMMENT ON COLUMN "public"."contacts"."skills" IS 'JSONB array of skills';



COMMENT ON COLUMN "public"."contacts"."analysis" IS 'JSONB object containing complete analysis including model, source, score, selling, hiring, and assessments data';



COMMENT ON COLUMN "public"."contacts"."activities" IS 'JSONB object containing social media activities and content posts';



COMMENT ON COLUMN "public"."contacts"."email_validation_response" IS 'Email validation response from email management API including mx record, domain type, status, and validation details';



COMMENT ON COLUMN "public"."contacts"."processing_status" IS 'Status of contact data processing. Values: pending, processing, completed, failed';



COMMENT ON COLUMN "public"."contacts"."pipeline_stage" IS 'Enum-like stage: PROSPECT | LEAD | APPOINTMENT_REQUESTED | APPOINTMENT_SCHEDULED | APPOINTMENT_CANCELLED | PRESENTATION_SCHEDULED | CONTRACT_NEGOTIATIONS | AGREEMENT_IN_PRINCIPLE | CLOSED_WON | CLOSED_LOST | REENGAGEMENT';



COMMENT ON COLUMN "public"."contacts"."ooo_until" IS 'Out-of-office return date; drafts should be blocked until this date when set';



COMMENT ON COLUMN "public"."contacts"."unsubscribed_at" IS 'Timestamp of unsubscribe; never auto-clear';



COMMENT ON COLUMN "public"."contacts"."stop_drafts" IS 'If true, do not generate or send drafts (OOO, unsubscribe, or stage gating)';



COMMENT ON COLUMN "public"."contacts"."last_email_sentiment" IS 'VERY_POSITIVE | POSITIVE | NEUTRAL | NEGATIVE | VERY_NEGATIVE';



COMMENT ON COLUMN "public"."contacts"."last_email_intent" IS 'Full JSON snapshot of last email analysis (relevance, classification, sub_intent, sentiment, ooo, policy)';



COMMENT ON COLUMN "public"."contacts"."last_thread_id" IS 'Last associated thread identifier from email system';



COMMENT ON COLUMN "public"."contacts"."last_incoming_email_at" IS 'Timestamp of most recent incoming email processed';



COMMENT ON COLUMN "public"."contacts"."stage_updated_at" IS 'Timestamp of last pipeline_stage change';



COMMENT ON COLUMN "public"."contacts"."phone" IS 'Contact phone number';



COMMENT ON COLUMN "public"."contacts"."b2b_email_requested" IS 'Flag indicating if email enrichment has been requested from B2B API for this contact. Set to true when request is sent to prevent duplicate requests.';



COMMENT ON COLUMN "public"."contacts"."hunter_email_requested" IS 'Flag indicating if email enrichment has been requested from Hunter.io API for this contact. Set to true when request is sent to prevent duplicate requests. Used as fallback when B2B enrichment fails.';



COMMENT ON COLUMN "public"."contacts"."hunter_email_response" IS 'Hunter.io API response stored as JSONB. Contains email finding results including email address, score, verification status, and metadata.';



COMMENT ON COLUMN "public"."contacts"."provider_responses" IS 'JSONB storage for email enrichment provider responses. Contains responses from various email finding services (Hunter.io, etc.) for tracking and debugging purposes.';



COMMENT ON COLUMN "public"."contacts"."icypeas_email_requested" IS 'Flag indicating if email enrichment has been requested from Icypeas API for this contact. Set to true when request is sent to prevent duplicate requests. Used as fallback when B2B enrichment and Hunter.io fail.';



COMMENT ON COLUMN "public"."contacts"."icypeas_email_response" IS 'Icypeas API response stored as JSONB. Contains email finding results including email address, certainty level, MX records, and metadata.';



COMMENT ON COLUMN "public"."contacts"."email_search_status" IS 'Status of email address search: search_not_started, started_searching_email, finished_searching_email';



COMMENT ON COLUMN "public"."contacts"."do_not_contact" IS 'Flag to mark contacts that should not be contacted. When true, all email communication is blocked and tasks are deleted.';



COMMENT ON COLUMN "public"."contacts"."sales_brief" IS 'Sales brief information stored as markdown text. Contains key information about the contact for sales purposes. Users can edit this directly.';



CREATE TABLE IF NOT EXISTS "public"."conversation_messages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "conversation_id" "uuid" NOT NULL,
    "organization_id" "text" NOT NULL,
    "sender_type" "text" NOT NULL,
    "sender_user_id" "text",
    "content" "text" NOT NULL,
    "subject" "text",
    "channel_type" "public"."channel_type" DEFAULT 'email'::"public"."channel_type" NOT NULL,
    "message_type" "text" DEFAULT 'text'::"text",
    "email_message_id" "text",
    "in_reply_to" "text",
    "metadata" "jsonb" DEFAULT '{}'::"jsonb",
    "sent_at" timestamp with time zone DEFAULT "now"(),
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "conversation_messages_sender_type_check" CHECK (("sender_type" = ANY (ARRAY['user'::"text", 'contact'::"text"])))
);


ALTER TABLE "public"."conversation_messages" OWNER TO "postgres";


COMMENT ON TABLE "public"."conversation_messages" IS 'Individual messages within conversations';



COMMENT ON COLUMN "public"."conversation_messages"."sender_type" IS 'Whether message was sent by user or contact';



COMMENT ON COLUMN "public"."conversation_messages"."email_message_id" IS 'Unique email message ID for tracking';



CREATE TABLE IF NOT EXISTS "public"."conversations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "contact_id" "uuid" NOT NULL,
    "organization_id" "text" NOT NULL,
    "user_id" "text",
    "subject" "text" NOT NULL,
    "channel_type" "public"."channel_type" DEFAULT 'email'::"public"."channel_type" NOT NULL,
    "status" "text" DEFAULT 'open'::"text",
    "priority" "text" DEFAULT 'normal'::"text",
    "account_email" "text",
    "is_unread" boolean DEFAULT true,
    "tags" "text"[] DEFAULT '{}'::"text"[],
    "metadata" "jsonb" DEFAULT '{}'::"jsonb",
    "last_message_at" timestamp with time zone DEFAULT "now"(),
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "conversations_priority_check" CHECK (("priority" = ANY (ARRAY['high'::"text", 'normal'::"text", 'low'::"text"]))),
    CONSTRAINT "conversations_status_check" CHECK (("status" = ANY (ARRAY['open'::"text", 'pending'::"text", 'closed'::"text"])))
);


ALTER TABLE "public"."conversations" OWNER TO "postgres";


COMMENT ON TABLE "public"."conversations" IS 'Stores conversation threads with contacts';



COMMENT ON COLUMN "public"."conversations"."account_email" IS 'Email account the conversation is happening through';



COMMENT ON COLUMN "public"."conversations"."tags" IS 'Array of tags for categorizing conversations';



CREATE TABLE IF NOT EXISTS "public"."token_usage" (
    "id" bigint NOT NULL,
    "organization_id" "text" NOT NULL,
    "session_id" "text" NOT NULL,
    "provider" "text" NOT NULL,
    "model_name" "text",
    "total_calls" integer DEFAULT 0,
    "total_input_tokens" integer DEFAULT 0,
    "total_output_tokens" integer DEFAULT 0,
    "total_tokens" integer DEFAULT 0,
    "tracking_start" timestamp with time zone NOT NULL,
    "tracking_end" timestamp with time zone NOT NULL,
    "metrics_raw" "jsonb" DEFAULT '{}'::"jsonb",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "run_id" "text",
    "agent_id" "text",
    "content" "text",
    "content_type" "text",
    "event" "text",
    "run_created_at" timestamp with time zone,
    "total_audio_tokens" integer DEFAULT 0,
    "total_cached_tokens" integer DEFAULT 0,
    "total_reasoning_tokens" integer DEFAULT 0,
    "total_prompt_tokens" integer DEFAULT 0,
    "total_completion_tokens" integer DEFAULT 0,
    "total_processing_time" numeric DEFAULT 0
);


ALTER TABLE "public"."token_usage" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."daily_token_usage" AS
 SELECT "token_usage"."organization_id",
    "date"("token_usage"."tracking_start") AS "usage_date",
    "token_usage"."provider",
    "token_usage"."model_name",
    "sum"("token_usage"."total_calls") AS "daily_calls",
    "sum"("token_usage"."total_tokens") AS "daily_tokens",
    "sum"("token_usage"."total_input_tokens") AS "daily_input_tokens",
    "sum"("token_usage"."total_output_tokens") AS "daily_output_tokens",
    "count"(DISTINCT "token_usage"."session_id") AS "unique_sessions"
   FROM "public"."token_usage"
  GROUP BY "token_usage"."organization_id", ("date"("token_usage"."tracking_start")), "token_usage"."provider", "token_usage"."model_name";


ALTER TABLE "public"."daily_token_usage" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."usage" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "text" NOT NULL,
    "session_id" "text" NOT NULL,
    "provider" "text" NOT NULL,
    "model_name" "text",
    "api_calls" integer DEFAULT 0,
    "input_tokens" integer DEFAULT 0,
    "output_tokens" integer DEFAULT 0,
    "total_tokens" integer DEFAULT 0,
    "run_id" "text",
    "agent_id" "text",
    "description" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "tracking_start" timestamp with time zone DEFAULT "now"(),
    "tracking_end" timestamp with time zone DEFAULT "now"(),
    "metadata" "jsonb" DEFAULT '{}'::"jsonb",
    "usage_context" "text" DEFAULT 'direct_api'::"text",
    "campaign_id" "text",
    "original_pricing" "jsonb" DEFAULT '{}'::"jsonb",
    "sellton_pricing" "jsonb" DEFAULT '{}'::"jsonb",
    "original_cost" numeric(12,6) DEFAULT 0,
    "sellton_cost" numeric(12,6) DEFAULT 0
);


ALTER TABLE "public"."usage" OWNER TO "postgres";


COMMENT ON TABLE "public"."usage" IS 'Universal usage tracking for all APIs and agents - handles both credit-based and token-based systems';



COMMENT ON COLUMN "public"."usage"."provider" IS 'Service provider: openai, deepseek, exa, b2b_enrichment, perplexity, togetherai, etc.';



COMMENT ON COLUMN "public"."usage"."model_name" IS 'Actual model name from API response (e.g., gpt-4o, deepseek-chat, exa-search)';



COMMENT ON COLUMN "public"."usage"."api_calls" IS 'Number of API calls made (primarily for credit-based APIs like Exa, B2B)';



COMMENT ON COLUMN "public"."usage"."input_tokens" IS 'Input tokens used (for token-based APIs like OpenAI, DeepSeek)';



COMMENT ON COLUMN "public"."usage"."output_tokens" IS 'Output tokens used (for token-based APIs like OpenAI, DeepSeek)';



COMMENT ON COLUMN "public"."usage"."total_tokens" IS 'Total tokens (input + output) or calculated equivalent';



COMMENT ON COLUMN "public"."usage"."usage_context" IS 'Usage context: agent_run, direct_api, batch_processing';



COMMENT ON COLUMN "public"."usage"."campaign_id" IS 'Campaign ID for tracking usage per campaign (nullable - not all usage is campaign-related)';



COMMENT ON COLUMN "public"."usage"."original_pricing" IS 'Original provider pricing at time of usage (JSONB with model pricing info)';



COMMENT ON COLUMN "public"."usage"."sellton_pricing" IS 'Sellton pricing applied at time of usage (JSONB with model pricing info)';



COMMENT ON COLUMN "public"."usage"."original_cost" IS 'Calculated cost using original provider pricing at time of usage';



COMMENT ON COLUMN "public"."usage"."sellton_cost" IS 'Calculated cost using Sellton pricing at time of usage';



CREATE OR REPLACE VIEW "public"."daily_usage_stats" AS
 SELECT "usage"."organization_id",
    "date"("usage"."created_at") AS "usage_date",
    "usage"."provider",
    "usage"."model_name",
    "sum"("usage"."api_calls") AS "daily_api_calls",
    "sum"("usage"."input_tokens") AS "daily_input_tokens",
    "sum"("usage"."output_tokens") AS "daily_output_tokens",
    "sum"("usage"."total_tokens") AS "daily_total_tokens",
    "count"(DISTINCT "usage"."session_id") AS "unique_sessions",
    "count"(*) AS "total_operations"
   FROM "public"."usage"
  GROUP BY "usage"."organization_id", ("date"("usage"."created_at")), "usage"."provider", "usage"."model_name";


ALTER TABLE "public"."daily_usage_stats" OWNER TO "postgres";


COMMENT ON VIEW "public"."daily_usage_stats" IS 'Daily usage statistics view for analytics and reporting';



CREATE TABLE IF NOT EXISTS "public"."document_access_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "short_url_id" "uuid" NOT NULL,
    "short_code" "text" NOT NULL,
    "contact_id" "uuid",
    "organization_id" "text" NOT NULL,
    "event_type" "text" NOT NULL,
    "file_id" "uuid" NOT NULL,
    "file_name" "text",
    "accessed_at" timestamp with time zone DEFAULT "now"(),
    "ip_address" "text",
    "user_agent" "text",
    "referrer" "text",
    "session_id" "text",
    "duration_seconds" integer,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb"
);


ALTER TABLE "public"."document_access_events" OWNER TO "postgres";


COMMENT ON TABLE "public"."document_access_events" IS 'Detailed tracking of every document access - who opened, when, for how long';



COMMENT ON COLUMN "public"."document_access_events"."event_type" IS 'Event type: "opened" (link clicked), "downloaded" (file downloaded), "viewed" (page viewed)';



COMMENT ON COLUMN "public"."document_access_events"."session_id" IS 'Browser session ID for tracking multiple events from same visit';



COMMENT ON COLUMN "public"."document_access_events"."duration_seconds" IS 'How long the document was viewed (if tracked by frontend)';



CREATE TABLE IF NOT EXISTS "public"."document_short_urls" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "short_code" "text" NOT NULL,
    "organization_id" "text" NOT NULL,
    "file_id" "uuid" NOT NULL,
    "file_name" "text" NOT NULL,
    "file_category" "text",
    "contact_id" "uuid",
    "campaign_id" "uuid",
    "shared_via" "text",
    "expires_at" timestamp with time zone NOT NULL,
    "access_count" integer DEFAULT 0,
    "last_accessed_at" timestamp with time zone,
    "first_accessed_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "created_by" "text"
);


ALTER TABLE "public"."document_short_urls" OWNER TO "postgres";


COMMENT ON TABLE "public"."document_short_urls" IS 'Short URL mappings for document sharing (like bit.ly) - replaces long JWT tokens with short codes';



COMMENT ON COLUMN "public"."document_short_urls"."short_code" IS 'Short alphanumeric code (e.g., "xK9mP2") - 6 characters, URL-safe';



COMMENT ON COLUMN "public"."document_short_urls"."contact_id" IS 'Contact this document was shared with (for tracking)';



COMMENT ON COLUMN "public"."document_short_urls"."shared_via" IS 'How it was shared: "email", "manual_share", "link_copy"';



COMMENT ON COLUMN "public"."document_short_urls"."expires_at" IS 'Expiration timestamp - default 30 days, extended to 90 days for case studies';



COMMENT ON COLUMN "public"."document_short_urls"."access_count" IS 'Total number of times this short URL was accessed';



CREATE TABLE IF NOT EXISTS "public"."feedback" (
    "id" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()),
    "interview_id" "text",
    "email" "text",
    "feedback" "text",
    "satisfaction" integer,
    "organization_id" "text" NOT NULL
);


ALTER TABLE "public"."feedback" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."feedback_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."feedback_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."feedback_id_seq" OWNED BY "public"."feedback"."id";



CREATE TABLE IF NOT EXISTS "public"."icp_profiles" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "text" NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "is_default" boolean DEFAULT false,
    "criteria" "jsonb" DEFAULT '{}'::"jsonb",
    "boosts_penalties" "jsonb" DEFAULT '{}'::"jsonb",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "icp_profiles_name_check" CHECK ((("char_length"("name") >= 1) AND ("char_length"("name") <= 255)))
);


ALTER TABLE "public"."icp_profiles" OWNER TO "postgres";


COMMENT ON TABLE "public"."icp_profiles" IS 'Ideal Customer Profile configurations with weighted scoring criteria. Each organization should have at least one default profile.';



COMMENT ON COLUMN "public"."icp_profiles"."id" IS 'Unique identifier for the ICP profile';



COMMENT ON COLUMN "public"."icp_profiles"."organization_id" IS 'Organization that owns this profile';



COMMENT ON COLUMN "public"."icp_profiles"."name" IS 'Profile name (1-255 characters, unique per organization)';



COMMENT ON COLUMN "public"."icp_profiles"."description" IS 'Optional description of the profile';



COMMENT ON COLUMN "public"."icp_profiles"."is_default" IS 'Whether this is the default profile for the organization';



COMMENT ON COLUMN "public"."icp_profiles"."criteria" IS 'JSONB object containing criterion configurations (industries, company_size, regions, etc.)';



COMMENT ON COLUMN "public"."icp_profiles"."boosts_penalties" IS 'Boosts and penalties for ICP scoring (deprecated - kept for backward compatibility but should be empty)';



CREATE TABLE IF NOT EXISTS "public"."interview" (
    "id" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()),
    "name" "text",
    "description" "text",
    "objective" "text",
    "user_id" "text",
    "interviewer_id" integer,
    "is_active" boolean DEFAULT true,
    "is_anonymous" boolean DEFAULT false,
    "is_archived" boolean DEFAULT false,
    "logo_url" "text",
    "theme_color" "text",
    "url" "text",
    "readable_slug" "text",
    "questions" "jsonb",
    "quotes" "jsonb"[],
    "insights" "text"[],
    "respondents" "text"[],
    "question_count" integer,
    "response_count" integer,
    "time_duration" "text",
    "organization_id" "text" NOT NULL
);


ALTER TABLE "public"."interview" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."interviewer" (
    "id" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()),
    "agent_id" "text",
    "name" "text" NOT NULL,
    "description" "text" NOT NULL,
    "image" "text" NOT NULL,
    "audio" "text",
    "empathy" integer NOT NULL,
    "exploration" integer NOT NULL,
    "rapport" integer NOT NULL,
    "speed" integer NOT NULL,
    "organization_id" "text" NOT NULL
);


ALTER TABLE "public"."interviewer" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."interviewer_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."interviewer_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."interviewer_id_seq" OWNED BY "public"."interviewer"."id";



CREATE TABLE IF NOT EXISTS "public"."organization" (
    "id" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()),
    "name" "text",
    "image_url" "text",
    "allowed_responses_count" integer,
    "plan" "public"."plan",
    "deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."organization" OWNER TO "postgres";


COMMENT ON COLUMN "public"."organization"."deleted" IS 'Flag to mark organization as deleted (set to true when organization is deleted from Clerk, instead of hard deleting the record)';



CREATE TABLE IF NOT EXISTS "public"."organization_files" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "text" NOT NULL,
    "file_name" "text" NOT NULL,
    "file_type" "text" NOT NULL,
    "file_url" "text" NOT NULL,
    "file_size" integer NOT NULL,
    "uploaded_at" timestamp with time zone DEFAULT "now"(),
    "shared_with_client" boolean DEFAULT false,
    "uploaded_by" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "file_category" "public"."file_category_enum" DEFAULT 'documents'::"public"."file_category_enum" NOT NULL,
    "full_text" "text",
    "pages_count" integer DEFAULT 0,
    "has_sensitive_data" boolean DEFAULT false,
    "sensitive_data_types" "text"[] DEFAULT '{}'::"text"[],
    "processing_status" "text" DEFAULT 'pending'::"text",
    "industries" "text"[] DEFAULT '{}'::"text"[],
    CONSTRAINT "organization_files_processing_status_check" CHECK (("processing_status" = ANY (ARRAY['pending'::"text", 'processing'::"text", 'processed'::"text", 'error'::"text"])))
);


ALTER TABLE "public"."organization_files" OWNER TO "postgres";


COMMENT ON TABLE "public"."organization_files" IS 'Stores metadata and full text content for uploaded documents. Used for AI training and email generation.';



COMMENT ON COLUMN "public"."organization_files"."file_category" IS 'Category of the file: documents, transcripts, internal_documents, sales_papers, sait_guidelines, brand_guidelines, case_study, sales_scripts, images, presentations, spreadsheets, proposals, other';



COMMENT ON COLUMN "public"."organization_files"."full_text" IS 'The complete text content extracted from the document';



COMMENT ON COLUMN "public"."organization_files"."pages_count" IS 'The total number of pages in the document (0 for non-paginated content)';



COMMENT ON COLUMN "public"."organization_files"."has_sensitive_data" IS 'Flag indicating if sensitive information (PII, financial data, etc.) was detected in this document during screening';



COMMENT ON COLUMN "public"."organization_files"."sensitive_data_types" IS 'Array of sensitive data types detected (e.g., email, phone, ssn, credit_card, api_key, etc.)';



COMMENT ON COLUMN "public"."organization_files"."processing_status" IS 'Status of document processing: pending (not started), processing (in progress), processed (completed), error (failed)';



COMMENT ON COLUMN "public"."organization_files"."industries" IS 'Array of industry codes that this case study is relevant for. Empty array means applicable to all industries. Only used for case_study file category.';



CREATE TABLE IF NOT EXISTS "public"."organization_icp_linkedin_urls" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "text" NOT NULL,
    "url" "text" NOT NULL,
    "url_type" "text" NOT NULL,
    "added_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "organization_icp_linkedin_urls_url_type_check" CHECK (("url_type" = ANY (ARRAY['current_customer'::"text", 'ideal_customer'::"text", 'ideal_person'::"text", 'exclusion'::"text"])))
);


ALTER TABLE "public"."organization_icp_linkedin_urls" OWNER TO "postgres";


COMMENT ON TABLE "public"."organization_icp_linkedin_urls" IS 'LinkedIn URLs for ICP settings (customers, ideal profiles, exclusions)';



COMMENT ON COLUMN "public"."organization_icp_linkedin_urls"."url_type" IS 'Type of LinkedIn URL: current_customer, ideal_customer, ideal_person, or exclusion';



CREATE TABLE IF NOT EXISTS "public"."organization_settings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "text" NOT NULL,
    "general_settings" "jsonb" DEFAULT '{}'::"jsonb",
    "notification_settings" "jsonb" DEFAULT '{}'::"jsonb",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "api_credentials" "jsonb" DEFAULT '{"cal_com_api_key": "", "calendly_api_key": ""}'::"jsonb",
    "onboarding_completed" boolean DEFAULT false,
    "onboarding_completed_at" timestamp with time zone,
    "company_website" "text",
    "company_linkedin_profile" "text",
    "company_description" "text",
    "onboarding_skipped" boolean DEFAULT false,
    "onboarding_skipped_at" timestamp with time zone,
    "contact_extraction_limit" integer DEFAULT 5 NOT NULL,
    "default_campaign_language" "text" DEFAULT 'en'::"text",
    "api_key" "text",
    "api_key_created_at" timestamp with time zone,
    "api_key_info_shown" boolean DEFAULT false NOT NULL,
    CONSTRAINT "check_contact_extraction_limit_range" CHECK ((("contact_extraction_limit" >= 1) AND ("contact_extraction_limit" <= 10)))
);


ALTER TABLE "public"."organization_settings" OWNER TO "postgres";


COMMENT ON TABLE "public"."organization_settings" IS 'Access restricted to API routes using service role. Direct access blocked by RLS.';



COMMENT ON COLUMN "public"."organization_settings"."api_credentials" IS 'API credentials for calendar integrations (Cal.com with API key and event type ID, Calendly)';



COMMENT ON COLUMN "public"."organization_settings"."onboarding_completed" IS 'Whether the user has completed the initial onboarding flow (not skipped)';



COMMENT ON COLUMN "public"."organization_settings"."onboarding_completed_at" IS 'When the onboarding was marked as completed';



COMMENT ON COLUMN "public"."organization_settings"."company_website" IS 'The official website of the company.';



COMMENT ON COLUMN "public"."organization_settings"."company_linkedin_profile" IS 'The LinkedIn profile URL of the company.';



COMMENT ON COLUMN "public"."organization_settings"."company_description" IS 'The description of the company and its activities.';



COMMENT ON COLUMN "public"."organization_settings"."onboarding_skipped" IS 'Whether the user explicitly skipped the onboarding flow';



COMMENT ON COLUMN "public"."organization_settings"."onboarding_skipped_at" IS 'When the onboarding was skipped';



COMMENT ON COLUMN "public"."organization_settings"."contact_extraction_limit" IS 'Maximum number of contacts to extract per company (default: 5, range: 1-10)';



COMMENT ON COLUMN "public"."organization_settings"."default_campaign_language" IS 'Default language code for new campaigns (en, en-gb, de, fr, sv). Default is en (English).';



COMMENT ON COLUMN "public"."organization_settings"."api_key" IS 'Unique API key for organization to access external APIs. Generated securely and stored as plain text for authentication purposes.';



COMMENT ON COLUMN "public"."organization_settings"."api_key_created_at" IS 'Timestamp when the API key was first created or last regenerated.';



COMMENT ON COLUMN "public"."organization_settings"."api_key_info_shown" IS 'Flag indicating if the user has been informed about the API key feature. Used to show informational notification only once.';



CREATE TABLE IF NOT EXISTS "public"."response" (
    "id" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()),
    "interview_id" "text",
    "name" "text",
    "email" "text",
    "call_id" "text",
    "candidate_status" "text",
    "duration" integer,
    "details" "jsonb",
    "analytics" "jsonb",
    "is_analysed" boolean DEFAULT false,
    "is_ended" boolean DEFAULT false,
    "is_viewed" boolean DEFAULT false,
    "tab_switch_count" integer,
    "organization_id" "text" NOT NULL
);


ALTER TABLE "public"."response" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."response_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."response_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."response_id_seq" OWNED BY "public"."response"."id";



CREATE TABLE IF NOT EXISTS "public"."style_guidelines_backup" (
    "id" integer,
    "created_at" timestamp with time zone,
    "organization_id" "text",
    "tone_of_voice_sound" "text",
    "tone_of_voice_emotions" "text"[],
    "tone_of_voice_personality_traits" "text"[],
    "key_word_choices_lexical_fields" "jsonb",
    "key_word_choices_dictionary" "jsonb",
    "writing_style_sentence_length" "text",
    "writing_style_sentence_complexity" "text",
    "writing_style_sentence_voice" "text",
    "writing_style_structural_devices" "text"[],
    "writing_style_formality" "text",
    "narrative_techniques_hooks" "text"[],
    "narrative_techniques_rhetorical_devices" "text"[],
    "narrative_techniques_social_proof" "text"[]
);


ALTER TABLE "public"."style_guidelines_backup" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."style_guidelines_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."style_guidelines_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."style_guidelines_id_seq" OWNED BY "public"."style_guidelines"."id";



CREATE TABLE IF NOT EXISTS "public"."system_config" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "key" "text" NOT NULL,
    "value" "jsonb" NOT NULL,
    "description" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."system_config" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."tasks" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "text" NOT NULL,
    "created_by_user_id" "text",
    "title" "text" NOT NULL,
    "description" "text",
    "status" "public"."task_status" DEFAULT 'pending'::"public"."task_status",
    "priority" "text",
    "contact_id" "uuid",
    "campaign_id" "uuid",
    "pre_generated_copy" "text",
    "due_date" timestamp with time zone,
    "completed_at" timestamp with time zone,
    "completed_by_user_id" "text",
    "metadata" "jsonb" DEFAULT '{}'::"jsonb",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "task_type" "public"."task_type",
    "company_id" "uuid",
    "reasoning_note" "text",
    "thread_id" "text",
    "email_id" "text",
    "sent_at" timestamp with time zone,
    "scheduled" boolean DEFAULT false NOT NULL,
    "subject" "text",
    "body" "text",
    "generation_log" "jsonb" DEFAULT '{}'::"jsonb",
    "priority_rank" integer DEFAULT 3 NOT NULL,
    "send_status" "text" DEFAULT 'not_sent'::"text",
    "send_error_message" "text",
    "conversation_summary" "jsonb" DEFAULT '{}'::"jsonb",
    "conversation_summary_text" "text",
    "feedback" "text",
    CONSTRAINT "tasks_feedback_check" CHECK ((("feedback" IS NULL) OR ("feedback" = ANY (ARRAY['liked'::"text", 'disliked'::"text"])))),
    CONSTRAINT "tasks_priority_check" CHECK ((("priority" IS NULL) OR ("priority" = ANY (ARRAY['low'::"text", 'normal'::"text", 'high'::"text", 'urgent'::"text"])))),
    CONSTRAINT "tasks_send_status_check" CHECK ((("send_status" IS NULL) OR ("send_status" = ANY (ARRAY['not_sent'::"text", 'sending'::"text", 'sent_success'::"text", 'sent_failed'::"text"])))),
    CONSTRAINT "tasks_valid_type_refs" CHECK (
CASE
    WHEN ("task_type" = 'review_draft'::"public"."task_type") THEN ("campaign_id" IS NOT NULL)
    WHEN ("task_type" = 'meeting'::"public"."task_type") THEN ("contact_id" IS NOT NULL)
    ELSE true
END)
);


ALTER TABLE "public"."tasks" OWNER TO "postgres";


COMMENT ON TABLE "public"."tasks" IS 'Tasks table with company_id and reasoning_note - supports linking tasks to companies and explaining task creation logic';



COMMENT ON COLUMN "public"."tasks"."created_by_user_id" IS 'User who created the task. NULL for automated/cron-generated tasks.';



COMMENT ON COLUMN "public"."tasks"."title" IS 'Display title for the task (e.g., "Review email draft for John Doe")';



COMMENT ON COLUMN "public"."tasks"."priority" IS 'Task priority level: calculated dynamically when fetched, or saved when task is completed/cancelled. Values: low, normal, high, urgent, or NULL for pending tasks.';



COMMENT ON COLUMN "public"."tasks"."pre_generated_copy" IS 'Original AI-generated email body. Kept as reference, never modified after initial generation.';



COMMENT ON COLUMN "public"."tasks"."company_id" IS 'Reference to the company this task is related to';



COMMENT ON COLUMN "public"."tasks"."reasoning_note" IS 'Explanation of why this task was created and the reasoning behind it';



COMMENT ON COLUMN "public"."tasks"."thread_id" IS 'Gmail thread ID (e.g., "198cc5c419a9ebf2")';



COMMENT ON COLUMN "public"."tasks"."email_id" IS 'Gmail email ID (e.g., "198d0348ceb32ea1")';



COMMENT ON COLUMN "public"."tasks"."sent_at" IS 'Timestamp when email was sent (immediate) or will be sent (scheduled). Used for follow-up timing calculations.';



COMMENT ON COLUMN "public"."tasks"."scheduled" IS 'Indicates whether the email was scheduled for future delivery (true) or sent immediately (false).';



COMMENT ON COLUMN "public"."tasks"."subject" IS 'Actual email subject line to be sent. Used for email-related tasks.';



COMMENT ON COLUMN "public"."tasks"."body" IS 'User-editable email body. This is what gets sent to Gmail API. Initially copied from pre_generated_copy.';



COMMENT ON COLUMN "public"."tasks"."generation_log" IS 'Comprehensive logging of email generation process including all steps, inputs, outputs, models used, templates, context data, and any errors';



COMMENT ON COLUMN "public"."tasks"."priority_rank" IS 'Numeric priority rank for database sorting: 1=urgent, 2=high, 3=normal, 4=low';



COMMENT ON COLUMN "public"."tasks"."send_status" IS 'Email send status: not_sent (default), sending, sent_success, sent_failed. Used by frontend to track email delivery state.';



COMMENT ON COLUMN "public"."tasks"."send_error_message" IS 'Error message if email send failed';



COMMENT ON COLUMN "public"."tasks"."conversation_summary" IS 'Stores conversation context including:
{
  "thread_id": "string",
  "topic": "string - what the conversation is about",
  "total_messages": number,
  "our_messages_count": number,
  "their_messages_count": number,
  "last_our_reply_at": "timestamp",
  "answered_questions": [
    {
      "question": "What is Sellton?",
      "answer": "Sellton is an autonomous...",
      "answered_at": "2025-12-13T..."
    }
  ],
  "unanswered_questions": ["Who is in your team?"],
  "current_intents": ["inquiry", "booking", "follow_up"],
  "scheduling_status": "slots_provided | waiting | booked | none",
  "last_updated": "timestamp"
}

NOTE: current_intents is an ARRAY to support multiple simultaneous intents.
Example: ["inquiry", "booking"] when user asks questions AND wants to schedule.';



COMMENT ON COLUMN "public"."tasks"."conversation_summary_text" IS 'Human-readable conversation summary for frontend display. Example:
"Discussed Sellton product features and scheduling. User asked about team size, company history, and use cases. We answered all questions and provided meeting slots for Dec 22-24. Waiting for time confirmation."';



COMMENT ON COLUMN "public"."tasks"."feedback" IS 'User feedback on task quality for training purposes.
Values: null (no feedback), ''liked'' (good quality), ''disliked'' (poor quality).
Used to identify good/bad email copy and company verification quality.';



CREATE SEQUENCE IF NOT EXISTS "public"."token_usage_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."token_usage_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."token_usage_id_seq" OWNED BY "public"."token_usage"."id";



CREATE OR REPLACE VIEW "public"."usage_cost_by_context" AS
 SELECT "usage"."organization_id",
    "usage"."usage_context",
    "sum"(COALESCE("usage"."original_cost", (0)::numeric)) AS "total_original_cost",
    "sum"(COALESCE("usage"."sellton_cost", (0)::numeric)) AS "total_sellton_cost",
    "sum"(COALESCE("usage"."input_tokens", 0)) AS "total_input_tokens",
    "sum"(COALESCE("usage"."output_tokens", 0)) AS "total_output_tokens",
    "sum"(COALESCE("usage"."total_tokens", 0)) AS "total_tokens",
    "sum"(COALESCE("usage"."api_calls", 0)) AS "total_api_calls",
    "count"(DISTINCT "usage"."provider") AS "unique_providers",
    "count"(DISTINCT "usage"."model_name") AS "unique_models",
    "count"(DISTINCT "usage"."campaign_id") AS "unique_campaigns",
    "count"(DISTINCT "usage"."session_id") AS "unique_sessions",
    "count"(*) AS "total_records",
    "min"("usage"."created_at") AS "first_usage_at",
    "max"("usage"."created_at") AS "last_usage_at"
   FROM "public"."usage"
  WHERE ("usage"."usage_context" IS NOT NULL)
  GROUP BY "usage"."organization_id", "usage"."usage_context";


ALTER TABLE "public"."usage_cost_by_context" OWNER TO "postgres";


COMMENT ON VIEW "public"."usage_cost_by_context" IS 'Total aggregated usage costs and token spend per organization and usage context';



CREATE OR REPLACE VIEW "public"."usage_cost_daily" AS
 SELECT "usage"."organization_id",
    "date"("usage"."created_at") AS "usage_date",
    "sum"(COALESCE("usage"."original_cost", (0)::numeric)) AS "total_original_cost",
    "sum"(COALESCE("usage"."sellton_cost", (0)::numeric)) AS "total_sellton_cost",
    "sum"(COALESCE("usage"."input_tokens", 0)) AS "total_input_tokens",
    "sum"(COALESCE("usage"."output_tokens", 0)) AS "total_output_tokens",
    "sum"(COALESCE("usage"."total_tokens", 0)) AS "total_tokens",
    "sum"(COALESCE("usage"."api_calls", 0)) AS "total_api_calls",
    "count"(DISTINCT "usage"."provider") AS "unique_providers",
    "count"(DISTINCT "usage"."model_name") AS "unique_models",
    "count"(DISTINCT "usage"."session_id") AS "unique_sessions",
    "count"(DISTINCT "usage"."campaign_id") AS "unique_campaigns",
    "count"(*) AS "total_records",
    "min"("usage"."created_at") AS "first_usage_at",
    "max"("usage"."created_at") AS "last_usage_at"
   FROM "public"."usage"
  WHERE (("usage"."created_at" IS NOT NULL) AND ("usage"."campaign_id" IS NOT NULL))
  GROUP BY "usage"."organization_id", ("date"("usage"."created_at"));


ALTER TABLE "public"."usage_cost_daily" OWNER TO "postgres";


COMMENT ON VIEW "public"."usage_cost_daily" IS 'Daily aggregated usage costs and token spend per organization (excluding records without campaign_id)';



CREATE OR REPLACE VIEW "public"."usage_cost_daily_by_campaign" AS
 SELECT "usage"."organization_id",
    "usage"."campaign_id",
    "date"("usage"."created_at") AS "usage_date",
    "sum"(COALESCE("usage"."original_cost", (0)::numeric)) AS "total_original_cost",
    "sum"(COALESCE("usage"."sellton_cost", (0)::numeric)) AS "total_sellton_cost",
    "sum"(COALESCE("usage"."input_tokens", 0)) AS "total_input_tokens",
    "sum"(COALESCE("usage"."output_tokens", 0)) AS "total_output_tokens",
    "sum"(COALESCE("usage"."total_tokens", 0)) AS "total_tokens",
    "sum"(COALESCE("usage"."api_calls", 0)) AS "total_api_calls",
    "count"(DISTINCT "usage"."provider") AS "unique_providers",
    "count"(DISTINCT "usage"."model_name") AS "unique_models",
    "count"(DISTINCT "usage"."session_id") AS "unique_sessions",
    "count"(*) AS "total_records",
    "min"("usage"."created_at") AS "first_usage_at",
    "max"("usage"."created_at") AS "last_usage_at"
   FROM "public"."usage"
  WHERE (("usage"."created_at" IS NOT NULL) AND ("usage"."campaign_id" IS NOT NULL))
  GROUP BY "usage"."organization_id", "usage"."campaign_id", ("date"("usage"."created_at"));


ALTER TABLE "public"."usage_cost_daily_by_campaign" OWNER TO "postgres";


COMMENT ON VIEW "public"."usage_cost_daily_by_campaign" IS 'Daily aggregated usage costs and token spend per organization and campaign';



CREATE OR REPLACE VIEW "public"."usage_cost_daily_by_context" AS
 SELECT "usage"."organization_id",
    "usage"."usage_context",
    "date"("usage"."created_at") AS "usage_date",
    "sum"(COALESCE("usage"."original_cost", (0)::numeric)) AS "total_original_cost",
    "sum"(COALESCE("usage"."sellton_cost", (0)::numeric)) AS "total_sellton_cost",
    "sum"(COALESCE("usage"."input_tokens", 0)) AS "total_input_tokens",
    "sum"(COALESCE("usage"."output_tokens", 0)) AS "total_output_tokens",
    "sum"(COALESCE("usage"."total_tokens", 0)) AS "total_tokens",
    "sum"(COALESCE("usage"."api_calls", 0)) AS "total_api_calls",
    "count"(DISTINCT "usage"."provider") AS "unique_providers",
    "count"(DISTINCT "usage"."model_name") AS "unique_models",
    "count"(DISTINCT "usage"."campaign_id") AS "unique_campaigns",
    "count"(DISTINCT "usage"."session_id") AS "unique_sessions",
    "count"(*) AS "total_records",
    "min"("usage"."created_at") AS "first_usage_at",
    "max"("usage"."created_at") AS "last_usage_at"
   FROM "public"."usage"
  WHERE (("usage"."usage_context" IS NOT NULL) AND ("usage"."created_at" IS NOT NULL))
  GROUP BY "usage"."organization_id", "usage"."usage_context", ("date"("usage"."created_at"));


ALTER TABLE "public"."usage_cost_daily_by_context" OWNER TO "postgres";


COMMENT ON VIEW "public"."usage_cost_daily_by_context" IS 'Daily aggregated usage costs and token spend per organization and usage context';



CREATE OR REPLACE VIEW "public"."usage_cost_daily_with_split" AS
 SELECT "usage"."organization_id",
    "date"("usage"."created_at") AS "usage_date",
        CASE
            WHEN ("usage"."campaign_id" IS NOT NULL) THEN 'campaign'::"text"
            ELSE 'non_campaign'::"text"
        END AS "cost_type",
    "sum"(COALESCE("usage"."original_cost", (0)::numeric)) AS "total_original_cost",
    "sum"(COALESCE("usage"."sellton_cost", (0)::numeric)) AS "total_sellton_cost",
    "sum"(COALESCE("usage"."input_tokens", 0)) AS "total_input_tokens",
    "sum"(COALESCE("usage"."output_tokens", 0)) AS "total_output_tokens",
    "sum"(COALESCE("usage"."total_tokens", 0)) AS "total_tokens",
    "sum"(COALESCE("usage"."api_calls", 0)) AS "total_api_calls",
    "count"(DISTINCT "usage"."provider") AS "unique_providers",
    "count"(DISTINCT "usage"."model_name") AS "unique_models",
    "count"(DISTINCT "usage"."session_id") AS "unique_sessions",
    "count"(DISTINCT "usage"."campaign_id") AS "unique_campaigns",
    "count"(*) AS "total_records",
    "min"("usage"."created_at") AS "first_usage_at",
    "max"("usage"."created_at") AS "last_usage_at"
   FROM "public"."usage"
  WHERE ("usage"."created_at" IS NOT NULL)
  GROUP BY "usage"."organization_id", ("date"("usage"."created_at")),
        CASE
            WHEN ("usage"."campaign_id" IS NOT NULL) THEN 'campaign'::"text"
            ELSE 'non_campaign'::"text"
        END;


ALTER TABLE "public"."usage_cost_daily_with_split" OWNER TO "postgres";


COMMENT ON VIEW "public"."usage_cost_daily_with_split" IS 'Daily aggregated usage costs split by campaign-related vs non-campaign-related costs';



CREATE OR REPLACE VIEW "public"."usage_cost_monthly" AS
 SELECT "usage"."organization_id",
    ("date_trunc"('month'::"text", "usage"."created_at"))::"date" AS "usage_month",
    "sum"(COALESCE("usage"."original_cost", (0)::numeric)) AS "total_original_cost",
    "sum"(COALESCE("usage"."sellton_cost", (0)::numeric)) AS "total_sellton_cost",
    "sum"(COALESCE("usage"."input_tokens", 0)) AS "total_input_tokens",
    "sum"(COALESCE("usage"."output_tokens", 0)) AS "total_output_tokens",
    "sum"(COALESCE("usage"."total_tokens", 0)) AS "total_tokens",
    "sum"(COALESCE("usage"."api_calls", 0)) AS "total_api_calls",
    "count"(DISTINCT "usage"."provider") AS "unique_providers",
    "count"(DISTINCT "usage"."model_name") AS "unique_models",
    "count"(DISTINCT "usage"."session_id") AS "unique_sessions",
    "count"(DISTINCT "usage"."campaign_id") AS "unique_campaigns",
    "count"(*) AS "total_records",
    "min"("usage"."created_at") AS "first_usage_at",
    "max"("usage"."created_at") AS "last_usage_at"
   FROM "public"."usage"
  WHERE (("usage"."created_at" IS NOT NULL) AND ("usage"."campaign_id" IS NOT NULL))
  GROUP BY "usage"."organization_id", ("date_trunc"('month'::"text", "usage"."created_at"));


ALTER TABLE "public"."usage_cost_monthly" OWNER TO "postgres";


COMMENT ON VIEW "public"."usage_cost_monthly" IS 'Monthly aggregated usage costs and token spend per organization (excluding records without campaign_id)';



CREATE OR REPLACE VIEW "public"."usage_cost_monthly_by_campaign" AS
 SELECT "usage"."organization_id",
    "usage"."campaign_id",
    ("date_trunc"('month'::"text", "usage"."created_at"))::"date" AS "usage_month",
    "sum"(COALESCE("usage"."original_cost", (0)::numeric)) AS "total_original_cost",
    "sum"(COALESCE("usage"."sellton_cost", (0)::numeric)) AS "total_sellton_cost",
    "sum"(COALESCE("usage"."input_tokens", 0)) AS "total_input_tokens",
    "sum"(COALESCE("usage"."output_tokens", 0)) AS "total_output_tokens",
    "sum"(COALESCE("usage"."total_tokens", 0)) AS "total_tokens",
    "sum"(COALESCE("usage"."api_calls", 0)) AS "total_api_calls",
    "count"(DISTINCT "usage"."provider") AS "unique_providers",
    "count"(DISTINCT "usage"."model_name") AS "unique_models",
    "count"(DISTINCT "usage"."session_id") AS "unique_sessions",
    "count"(*) AS "total_records",
    "min"("usage"."created_at") AS "first_usage_at",
    "max"("usage"."created_at") AS "last_usage_at"
   FROM "public"."usage"
  WHERE (("usage"."created_at" IS NOT NULL) AND ("usage"."campaign_id" IS NOT NULL))
  GROUP BY "usage"."organization_id", "usage"."campaign_id", ("date_trunc"('month'::"text", "usage"."created_at"));


ALTER TABLE "public"."usage_cost_monthly_by_campaign" OWNER TO "postgres";


COMMENT ON VIEW "public"."usage_cost_monthly_by_campaign" IS 'Monthly aggregated usage costs and token spend per organization and campaign';



CREATE OR REPLACE VIEW "public"."usage_cost_monthly_by_context" AS
 SELECT "usage"."organization_id",
    "usage"."usage_context",
    ("date_trunc"('month'::"text", "usage"."created_at"))::"date" AS "usage_month",
    "sum"(COALESCE("usage"."original_cost", (0)::numeric)) AS "total_original_cost",
    "sum"(COALESCE("usage"."sellton_cost", (0)::numeric)) AS "total_sellton_cost",
    "sum"(COALESCE("usage"."input_tokens", 0)) AS "total_input_tokens",
    "sum"(COALESCE("usage"."output_tokens", 0)) AS "total_output_tokens",
    "sum"(COALESCE("usage"."total_tokens", 0)) AS "total_tokens",
    "sum"(COALESCE("usage"."api_calls", 0)) AS "total_api_calls",
    "count"(DISTINCT "usage"."provider") AS "unique_providers",
    "count"(DISTINCT "usage"."model_name") AS "unique_models",
    "count"(DISTINCT "usage"."campaign_id") AS "unique_campaigns",
    "count"(DISTINCT "usage"."session_id") AS "unique_sessions",
    "count"(*) AS "total_records",
    "min"("usage"."created_at") AS "first_usage_at",
    "max"("usage"."created_at") AS "last_usage_at"
   FROM "public"."usage"
  WHERE (("usage"."usage_context" IS NOT NULL) AND ("usage"."created_at" IS NOT NULL))
  GROUP BY "usage"."organization_id", "usage"."usage_context", ("date_trunc"('month'::"text", "usage"."created_at"));


ALTER TABLE "public"."usage_cost_monthly_by_context" OWNER TO "postgres";


COMMENT ON VIEW "public"."usage_cost_monthly_by_context" IS 'Monthly aggregated usage costs and token spend per organization and usage context';



CREATE OR REPLACE VIEW "public"."usage_cost_monthly_with_split" AS
 SELECT "usage"."organization_id",
    ("date_trunc"('month'::"text", "usage"."created_at"))::"date" AS "usage_month",
        CASE
            WHEN ("usage"."campaign_id" IS NOT NULL) THEN 'campaign'::"text"
            ELSE 'non_campaign'::"text"
        END AS "cost_type",
    "sum"(COALESCE("usage"."original_cost", (0)::numeric)) AS "total_original_cost",
    "sum"(COALESCE("usage"."sellton_cost", (0)::numeric)) AS "total_sellton_cost",
    "sum"(COALESCE("usage"."input_tokens", 0)) AS "total_input_tokens",
    "sum"(COALESCE("usage"."output_tokens", 0)) AS "total_output_tokens",
    "sum"(COALESCE("usage"."total_tokens", 0)) AS "total_tokens",
    "sum"(COALESCE("usage"."api_calls", 0)) AS "total_api_calls",
    "count"(DISTINCT "usage"."provider") AS "unique_providers",
    "count"(DISTINCT "usage"."model_name") AS "unique_models",
    "count"(DISTINCT "usage"."session_id") AS "unique_sessions",
    "count"(DISTINCT "usage"."campaign_id") AS "unique_campaigns",
    "count"(*) AS "total_records",
    "min"("usage"."created_at") AS "first_usage_at",
    "max"("usage"."created_at") AS "last_usage_at"
   FROM "public"."usage"
  WHERE ("usage"."created_at" IS NOT NULL)
  GROUP BY "usage"."organization_id", ("date_trunc"('month'::"text", "usage"."created_at")),
        CASE
            WHEN ("usage"."campaign_id" IS NOT NULL) THEN 'campaign'::"text"
            ELSE 'non_campaign'::"text"
        END;


ALTER TABLE "public"."usage_cost_monthly_with_split" OWNER TO "postgres";


COMMENT ON VIEW "public"."usage_cost_monthly_with_split" IS 'Monthly aggregated usage costs split by campaign-related vs non-campaign-related costs';



CREATE SEQUENCE IF NOT EXISTS "public"."usage_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."usage_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."usage_id_seq" OWNED BY "public"."usage"."id";



CREATE TABLE IF NOT EXISTS "public"."usage_summary" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "text" NOT NULL,
    "provider" "text" NOT NULL,
    "model_name" "text",
    "date" "date" NOT NULL,
    "total_api_calls" integer DEFAULT 0,
    "total_input_tokens" integer DEFAULT 0,
    "total_output_tokens" integer DEFAULT 0,
    "total_tokens" integer DEFAULT 0,
    "unique_sessions" integer DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."usage_summary" OWNER TO "postgres";


COMMENT ON TABLE "public"."usage_summary" IS 'Daily aggregated usage summaries automatically updated via triggers';



CREATE SEQUENCE IF NOT EXISTS "public"."usage_summary_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."usage_summary_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."usage_summary_id_seq" OWNED BY "public"."usage_summary"."id";



CREATE TABLE IF NOT EXISTS "public"."user" (
    "id" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()),
    "email" "text"
);


ALTER TABLE "public"."user" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_organizations" (
    "user_id" "text" NOT NULL,
    "organization_id" "text" NOT NULL
);


ALTER TABLE "public"."user_organizations" OWNER TO "postgres";


COMMENT ON TABLE "public"."user_organizations" IS 'Links users to their organizations. Fixed by migration 70 to ensure all users have proper associations.';



ALTER TABLE ONLY "public"."feedback" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."feedback_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."interviewer" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."interviewer_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."response" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."response_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."style_guidelines" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."style_guidelines_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."token_usage" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."token_usage_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."campaign_activities"
    ADD CONSTRAINT "campaign_activities_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."campaign_companies"
    ADD CONSTRAINT "campaign_companies_campaign_id_company_id_key" UNIQUE ("campaign_id", "company_id");



ALTER TABLE ONLY "public"."campaign_companies"
    ADD CONSTRAINT "campaign_companies_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."campaign_emails"
    ADD CONSTRAINT "campaign_emails_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."campaign_files"
    ADD CONSTRAINT "campaign_files_campaign_id_file_id_key" UNIQUE ("campaign_id", "file_id");



ALTER TABLE ONLY "public"."campaign_files"
    ADD CONSTRAINT "campaign_files_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."campaign_seed_companies"
    ADD CONSTRAINT "campaign_seed_companies_campaign_id_seed_company_url_key" UNIQUE ("campaign_id", "seed_company_url");



ALTER TABLE ONLY "public"."campaign_seed_companies"
    ADD CONSTRAINT "campaign_seed_companies_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."campaigns"
    ADD CONSTRAINT "campaigns_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."companies"
    ADD CONSTRAINT "companies_organization_id_name_key" UNIQUE ("organization_id", "name");



ALTER TABLE ONLY "public"."companies"
    ADD CONSTRAINT "companies_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."company_activities"
    ADD CONSTRAINT "company_activities_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."company_contacts"
    ADD CONSTRAINT "company_contacts_company_id_contact_id_key" UNIQUE ("company_id", "contact_id");



ALTER TABLE ONLY "public"."company_contacts"
    ADD CONSTRAINT "company_contacts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."contact_activities"
    ADD CONSTRAINT "contact_activities_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."contact_channels"
    ADD CONSTRAINT "contact_channels_contact_id_channel_type_channel_value_key" UNIQUE ("contact_id", "channel_type", "channel_value");



ALTER TABLE ONLY "public"."contact_channels"
    ADD CONSTRAINT "contact_channels_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."contact_notes"
    ADD CONSTRAINT "contact_notes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."contacts"
    ADD CONSTRAINT "contacts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."conversation_messages"
    ADD CONSTRAINT "conversation_messages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."conversations"
    ADD CONSTRAINT "conversations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."document_access_events"
    ADD CONSTRAINT "document_access_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."document_short_urls"
    ADD CONSTRAINT "document_short_urls_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."document_short_urls"
    ADD CONSTRAINT "document_short_urls_short_code_key" UNIQUE ("short_code");



ALTER TABLE ONLY "public"."feedback"
    ADD CONSTRAINT "feedback_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."icp_profiles"
    ADD CONSTRAINT "icp_profiles_organization_id_name_key" UNIQUE ("organization_id", "name");



ALTER TABLE ONLY "public"."icp_profiles"
    ADD CONSTRAINT "icp_profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."interview"
    ADD CONSTRAINT "interview_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."interviewer"
    ADD CONSTRAINT "interviewer_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."organization_files"
    ADD CONSTRAINT "organization_files_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."organization_icp_linkedin_urls"
    ADD CONSTRAINT "organization_icp_linkedin_urls_organization_id_url_url_type_key" UNIQUE ("organization_id", "url", "url_type");



ALTER TABLE ONLY "public"."organization_icp_linkedin_urls"
    ADD CONSTRAINT "organization_icp_linkedin_urls_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."organization"
    ADD CONSTRAINT "organization_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."organization_settings"
    ADD CONSTRAINT "organization_settings_api_key_key" UNIQUE ("api_key");



ALTER TABLE ONLY "public"."organization_settings"
    ADD CONSTRAINT "organization_settings_organization_id_key" UNIQUE ("organization_id");



ALTER TABLE ONLY "public"."organization_settings"
    ADD CONSTRAINT "organization_settings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."response"
    ADD CONSTRAINT "response_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."style_guidelines"
    ADD CONSTRAINT "style_guidelines_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."system_config"
    ADD CONSTRAINT "system_config_key_key" UNIQUE ("key");



ALTER TABLE ONLY "public"."system_config"
    ADD CONSTRAINT "system_config_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."tasks"
    ADD CONSTRAINT "tasks_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."token_usage"
    ADD CONSTRAINT "token_usage_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."usage"
    ADD CONSTRAINT "usage_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."usage_summary"
    ADD CONSTRAINT "usage_summary_organization_id_provider_model_name_date_key" UNIQUE ("organization_id", "provider", "model_name", "date");



ALTER TABLE ONLY "public"."usage_summary"
    ADD CONSTRAINT "usage_summary_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_organizations"
    ADD CONSTRAINT "user_organizations_pkey" PRIMARY KEY ("user_id", "organization_id");



ALTER TABLE ONLY "public"."user"
    ADD CONSTRAINT "user_pkey" PRIMARY KEY ("id");



CREATE INDEX "feedback_organization_id_idx" ON "public"."feedback" USING "btree" ("organization_id");



CREATE INDEX "idx_access_events_accessed_at" ON "public"."document_access_events" USING "btree" ("accessed_at" DESC);



CREATE INDEX "idx_access_events_contact" ON "public"."document_access_events" USING "btree" ("contact_id");



CREATE INDEX "idx_access_events_event_type" ON "public"."document_access_events" USING "btree" ("event_type");



CREATE INDEX "idx_access_events_org" ON "public"."document_access_events" USING "btree" ("organization_id");



CREATE INDEX "idx_access_events_short_url" ON "public"."document_access_events" USING "btree" ("short_url_id");



CREATE INDEX "idx_campaign_activities_activity_type" ON "public"."campaign_activities" USING "btree" ("activity_type");



CREATE INDEX "idx_campaign_activities_campaign_id" ON "public"."campaign_activities" USING "btree" ("campaign_id");



CREATE INDEX "idx_campaign_activities_contact_id" ON "public"."campaign_activities" USING "btree" ("contact_id");



CREATE INDEX "idx_campaign_activities_meetings" ON "public"."campaign_activities" USING "btree" ("campaign_id", "activity_type") WHERE ("activity_type" = 'meeting_booked'::"text");



CREATE INDEX "idx_campaign_activities_occurred_at" ON "public"."campaign_activities" USING "btree" ("occurred_at");



CREATE INDEX "idx_campaign_activities_organization_id" ON "public"."campaign_activities" USING "btree" ("organization_id");



CREATE INDEX "idx_campaign_companies_batch_lookup" ON "public"."campaign_companies" USING "btree" ("organization_id", "campaign_id", "company_id");



CREATE INDEX "idx_campaign_companies_blocked_by_icp" ON "public"."campaign_companies" USING "btree" ("blocked_by_icp") WHERE ("blocked_by_icp" = true);



CREATE INDEX "idx_campaign_companies_campaign_id" ON "public"."campaign_companies" USING "btree" ("campaign_id");



CREATE INDEX "idx_campaign_companies_company_id" ON "public"."campaign_companies" USING "btree" ("company_id");



CREATE INDEX "idx_campaign_companies_icp_profile_id" ON "public"."campaign_companies" USING "btree" ("icp_profile_id_used");



CREATE INDEX "idx_campaign_companies_org_campaign" ON "public"."campaign_companies" USING "btree" ("organization_id", "campaign_id");



CREATE INDEX "idx_campaign_companies_organization_id" ON "public"."campaign_companies" USING "btree" ("organization_id");



CREATE INDEX "idx_campaign_emails_approved_at" ON "public"."campaign_emails" USING "btree" ("approved_at");



CREATE INDEX "idx_campaign_emails_campaign_id" ON "public"."campaign_emails" USING "btree" ("campaign_id");



CREATE INDEX "idx_campaign_emails_contact_id" ON "public"."campaign_emails" USING "btree" ("contact_id");



CREATE INDEX "idx_campaign_emails_opened" ON "public"."campaign_emails" USING "btree" ("campaign_id", "opened_at") WHERE ("opened_at" IS NOT NULL);



CREATE INDEX "idx_campaign_emails_opened_at" ON "public"."campaign_emails" USING "btree" ("opened_at") WHERE ("opened_at" IS NOT NULL);



CREATE INDEX "idx_campaign_emails_organization_id" ON "public"."campaign_emails" USING "btree" ("organization_id");



CREATE INDEX "idx_campaign_emails_replied" ON "public"."campaign_emails" USING "btree" ("campaign_id", "replied_at") WHERE ("replied_at" IS NOT NULL);



CREATE INDEX "idx_campaign_emails_replied_at" ON "public"."campaign_emails" USING "btree" ("replied_at") WHERE ("replied_at" IS NOT NULL);



CREATE INDEX "idx_campaign_emails_sent_at" ON "public"."campaign_emails" USING "btree" ("sent_at");



CREATE INDEX "idx_campaign_emails_status" ON "public"."campaign_emails" USING "btree" ("status");



CREATE INDEX "idx_campaign_emails_status_campaign_id" ON "public"."campaign_emails" USING "btree" ("status", "campaign_id");



CREATE INDEX "idx_campaign_emails_thread_id" ON "public"."campaign_emails" USING "btree" ("thread_id");



CREATE INDEX "idx_campaign_files_campaign_id" ON "public"."campaign_files" USING "btree" ("campaign_id");



CREATE INDEX "idx_campaign_files_created_at" ON "public"."campaign_files" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_campaign_files_file_id" ON "public"."campaign_files" USING "btree" ("file_id");



CREATE INDEX "idx_campaign_seed_companies_campaign_id" ON "public"."campaign_seed_companies" USING "btree" ("campaign_id");



CREATE INDEX "idx_campaign_seed_companies_is_active" ON "public"."campaign_seed_companies" USING "btree" ("campaign_id", "is_active") WHERE ("is_active" = true);



CREATE INDEX "idx_campaign_seed_companies_org_id" ON "public"."campaign_seed_companies" USING "btree" ("organization_id");



CREATE INDEX "idx_campaign_seed_companies_organization_id" ON "public"."campaign_seed_companies" USING "btree" ("organization_id");



CREATE INDEX "idx_campaign_seed_companies_processing_order" ON "public"."campaign_seed_companies" USING "btree" ("campaign_id", "processing_order");



CREATE INDEX "idx_campaigns_autopilot_enabled" ON "public"."campaigns" USING "btree" ("autopilot_enabled") WHERE ("autopilot_enabled" = true);



CREATE INDEX "idx_campaigns_b2b_results" ON "public"."campaigns" USING "gin" ("b2b_results");



CREATE INDEX "idx_campaigns_b2b_search_filters" ON "public"."campaigns" USING "gin" ("b2b_search_filters");



CREATE INDEX "idx_campaigns_b2b_total_elements" ON "public"."campaigns" USING "btree" ("b2b_search_total_elements");



CREATE INDEX "idx_campaigns_created_at" ON "public"."campaigns" USING "btree" ("created_at");



CREATE INDEX "idx_campaigns_csv_processed_index" ON "public"."campaigns" USING "gin" ("csv_processed_index");



CREATE INDEX "idx_campaigns_csv_results" ON "public"."campaigns" USING "gin" ("csv_results");



CREATE INDEX "idx_campaigns_csv_template_upload" ON "public"."campaigns" USING "btree" ("organization_id", "csv_template_upload") WHERE ("csv_template_upload" = true);



CREATE INDEX "idx_campaigns_curated_companies" ON "public"."campaigns" USING "gin" ("curated_companies");



CREATE INDEX "idx_campaigns_current_workflow_node_id" ON "public"."campaigns" USING "btree" ("current_workflow_node_id") WHERE ("current_workflow_node_id" IS NOT NULL);



CREATE INDEX "idx_campaigns_deep_research_override" ON "public"."campaigns" USING "btree" ("deep_research_override") WHERE ("deep_research_override" = true);



CREATE INDEX "idx_campaigns_deep_research_provider" ON "public"."campaigns" USING "btree" ("deep_research_provider") WHERE ("deep_research_provider" IS NOT NULL);



CREATE INDEX "idx_campaigns_discover_mobile_numbers" ON "public"."campaigns" USING "btree" ("discover_mobile_numbers");



CREATE INDEX "idx_campaigns_estimated_total_companies" ON "public"."campaigns" USING "btree" ("estimated_total_companies");



CREATE INDEX "idx_campaigns_icp_city" ON "public"."campaigns" USING "btree" ("icp_city");



CREATE INDEX "idx_campaigns_icp_country" ON "public"."campaigns" USING "btree" ("icp_country");



CREATE INDEX "idx_campaigns_icp_industries" ON "public"."campaigns" USING "gin" ("icp_industries");



CREATE INDEX "idx_campaigns_icp_job_titles" ON "public"."campaigns" USING "gin" ("icp_job_titles");



CREATE INDEX "idx_campaigns_icp_profile_id" ON "public"."campaigns" USING "btree" ("icp_profile_id") WHERE ("icp_profile_id" IS NOT NULL);



CREATE INDEX "idx_campaigns_icp_regions" ON "public"."campaigns" USING "gin" ("icp_primary_regions");



CREATE INDEX "idx_campaigns_language" ON "public"."campaigns" USING "btree" ("language");



CREATE INDEX "idx_campaigns_launched_at" ON "public"."campaigns" USING "btree" ("launched_at");



CREATE INDEX "idx_campaigns_lead_source" ON "public"."campaigns" USING "btree" ("lead_source");



CREATE INDEX "idx_campaigns_location_type" ON "public"."campaigns" USING "btree" ("location_type");



CREATE INDEX "idx_campaigns_lookalike_total_found" ON "public"."campaigns" USING "btree" ("lookalike_total_found");



CREATE INDEX "idx_campaigns_lookalike_total_processed" ON "public"."campaigns" USING "btree" ("lookalike_total_processed");



CREATE INDEX "idx_campaigns_org_status" ON "public"."campaigns" USING "btree" ("organization_id", "status");



CREATE INDEX "idx_campaigns_organization_id" ON "public"."campaigns" USING "btree" ("organization_id");



CREATE INDEX "idx_campaigns_phone_discovery_mode" ON "public"."campaigns" USING "btree" ("phone_discovery_mode");



CREATE INDEX "idx_campaigns_schedule_hour" ON "public"."campaigns" USING "btree" ("email_schedule_hour");



CREATE INDEX "idx_campaigns_selected_company_ids" ON "public"."campaigns" USING "gin" ("selected_company_ids");



CREATE INDEX "idx_campaigns_started_at" ON "public"."campaigns" USING "btree" ("started_at");



CREATE INDEX "idx_campaigns_status" ON "public"."campaigns" USING "btree" ("status");



CREATE INDEX "idx_campaigns_timezone" ON "public"."campaigns" USING "btree" ("campaign_timezone");



CREATE INDEX "idx_campaigns_total_companies" ON "public"."campaigns" USING "btree" ("total_companies");



CREATE INDEX "idx_campaigns_user_id" ON "public"."campaigns" USING "btree" ("user_id");



CREATE INDEX "idx_campaigns_wizard_completed" ON "public"."campaigns" USING "btree" ("wizard_completed");



CREATE INDEX "idx_companies_b2b_result" ON "public"."companies" USING "gin" ("b2b_result");



CREATE INDEX "idx_companies_blocked_by_icp" ON "public"."companies" USING "btree" ("blocked_by_icp") WHERE ("blocked_by_icp" = true);



CREATE INDEX "idx_companies_blocked_icp" ON "public"."companies" USING "btree" ("blocked_by_icp") WHERE ("blocked_by_icp" = true);



CREATE INDEX "idx_companies_contact_extraction_status" ON "public"."companies" USING "btree" ("contact_extraction_status") WHERE ("contact_extraction_status" IS NOT NULL);



CREATE INDEX "idx_companies_created_at" ON "public"."companies" USING "btree" ("created_at");



CREATE INDEX "idx_companies_deep_research_gin" ON "public"."companies" USING "gin" ("deep_research");



CREATE INDEX "idx_companies_deep_research_v2" ON "public"."companies" USING "gin" ("deep_research_v2");



CREATE INDEX "idx_companies_employee_count" ON "public"."companies" USING "btree" ("employee_count");



CREATE INDEX "idx_companies_failed_reason" ON "public"."companies" USING "btree" ("organization_id", "processing_status", "failure_reason") WHERE ("processing_status" = 'failed'::"text");



CREATE INDEX "idx_companies_icp_score_gin" ON "public"."companies" USING "gin" ("icp_score");



CREATE INDEX "idx_companies_industries" ON "public"."companies" USING "gin" ("industries");



CREATE INDEX "idx_companies_industries_gin" ON "public"."companies" USING "gin" ("industries");



CREATE INDEX "idx_companies_linkedin_url" ON "public"."companies" USING "btree" ("linkedin_url") WHERE ("linkedin_url" IS NOT NULL);



CREATE INDEX "idx_companies_matches_case_study" ON "public"."companies" USING "btree" ("matches_case_study") WHERE ("matches_case_study" = true);



CREATE INDEX "idx_companies_name" ON "public"."companies" USING "btree" ("name");



CREATE INDEX "idx_companies_org_blocked" ON "public"."companies" USING "btree" ("organization_id", "blocked_by_icp");



CREATE INDEX "idx_companies_org_case_study" ON "public"."companies" USING "btree" ("organization_id", "matches_case_study") WHERE ("matches_case_study" = true);



CREATE INDEX "idx_companies_org_created" ON "public"."companies" USING "btree" ("organization_id", "created_at");



CREATE INDEX "idx_companies_org_name" ON "public"."companies" USING "btree" ("organization_id", "name");



CREATE INDEX "idx_companies_org_status" ON "public"."companies" USING "btree" ("organization_id", "processing_status");



COMMENT ON INDEX "public"."idx_companies_org_status" IS 'Optimizes cron job queries filtering by organization and processing status';



CREATE INDEX "idx_companies_org_updated" ON "public"."companies" USING "btree" ("organization_id", "updated_at");



CREATE INDEX "idx_companies_organization_id" ON "public"."companies" USING "btree" ("organization_id");



CREATE INDEX "idx_companies_outreach_strategy" ON "public"."companies" USING "gin" ("outreach_strategy");



CREATE INDEX "idx_companies_processing_log" ON "public"."companies" USING "gin" ("processing_log");



CREATE INDEX "idx_companies_processing_status" ON "public"."companies" USING "btree" ("processing_status") WHERE ("processing_status" IS NOT NULL);



CREATE INDEX "idx_companies_sales_brief" ON "public"."companies" USING "btree" ("sales_brief") WHERE ("sales_brief" IS NOT NULL);



CREATE INDEX "idx_companies_search_gin" ON "public"."companies" USING "gin" ("name" "public"."gin_trgm_ops", "location" "public"."gin_trgm_ops", "description" "public"."gin_trgm_ops");



CREATE INDEX "idx_companies_used_for_outreach" ON "public"."companies" USING "btree" ("used_for_outreach");



CREATE INDEX "idx_companies_useful_case_file_ids" ON "public"."companies" USING "gin" ("useful_case_file_ids");



CREATE INDEX "idx_companies_website" ON "public"."companies" USING "btree" ("website");



CREATE INDEX "idx_company_activities_activity_type" ON "public"."company_activities" USING "btree" ("activity_type");



CREATE INDEX "idx_company_activities_campaign_id" ON "public"."company_activities" USING "btree" ("campaign_id");



CREATE INDEX "idx_company_activities_company_created_at" ON "public"."company_activities" USING "btree" ("company_id", "created_at" DESC);



CREATE INDEX "idx_company_activities_company_id" ON "public"."company_activities" USING "btree" ("company_id");



CREATE INDEX "idx_company_activities_contact_id" ON "public"."company_activities" USING "btree" ("contact_id");



CREATE INDEX "idx_company_activities_created_at" ON "public"."company_activities" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_company_activities_created_by_user_id" ON "public"."company_activities" USING "btree" ("created_by_user_id");



CREATE INDEX "idx_company_activities_metadata_gin" ON "public"."company_activities" USING "gin" ("metadata");



CREATE INDEX "idx_company_activities_organization_id" ON "public"."company_activities" USING "btree" ("organization_id");



CREATE INDEX "idx_company_activities_task_id" ON "public"."company_activities" USING "btree" ("task_id");



CREATE INDEX "idx_company_contacts_company" ON "public"."company_contacts" USING "btree" ("company_id");



CREATE INDEX "idx_company_contacts_company_id" ON "public"."company_contacts" USING "btree" ("company_id");



CREATE INDEX "idx_company_contacts_contact_id" ON "public"."company_contacts" USING "btree" ("contact_id");



CREATE INDEX "idx_company_contacts_organization_id" ON "public"."company_contacts" USING "btree" ("organization_id");



CREATE INDEX "idx_contact_activities_activity_type" ON "public"."contact_activities" USING "btree" ("activity_type");



CREATE INDEX "idx_contact_activities_contact_id" ON "public"."contact_activities" USING "btree" ("contact_id");



CREATE INDEX "idx_contact_activities_occurred_at" ON "public"."contact_activities" USING "btree" ("occurred_at");



CREATE INDEX "idx_contact_activities_organization_id" ON "public"."contact_activities" USING "btree" ("organization_id");



CREATE INDEX "idx_contact_activities_user_id" ON "public"."contact_activities" USING "btree" ("user_id");



CREATE INDEX "idx_contact_channels_channel_type" ON "public"."contact_channels" USING "btree" ("channel_type");



CREATE INDEX "idx_contact_channels_contact_id" ON "public"."contact_channels" USING "btree" ("contact_id");



CREATE INDEX "idx_contact_channels_organization_id" ON "public"."contact_channels" USING "btree" ("organization_id");



CREATE INDEX "idx_contact_notes_contact_id" ON "public"."contact_notes" USING "btree" ("contact_id");



CREATE INDEX "idx_contact_notes_created_at" ON "public"."contact_notes" USING "btree" ("created_at");



CREATE INDEX "idx_contact_notes_organization_id" ON "public"."contact_notes" USING "btree" ("organization_id");



CREATE INDEX "idx_contacts_activities_gin" ON "public"."contacts" USING "gin" ("activities");



CREATE INDEX "idx_contacts_analysis_gin" ON "public"."contacts" USING "gin" ("analysis");



CREATE INDEX "idx_contacts_b2b_email_requested" ON "public"."contacts" USING "btree" ("organization_id", "b2b_email_requested") WHERE ("b2b_email_requested" = false);



CREATE INDEX "idx_contacts_certifications_gin" ON "public"."contacts" USING "gin" ("certifications");



CREATE INDEX "idx_contacts_created_at" ON "public"."contacts" USING "btree" ("created_at");



CREATE INDEX "idx_contacts_do_not_contact" ON "public"."contacts" USING "btree" ("do_not_contact") WHERE ("do_not_contact" = true);



CREATE INDEX "idx_contacts_educations_gin" ON "public"."contacts" USING "gin" ("educations");



CREATE INDEX "idx_contacts_email" ON "public"."contacts" USING "btree" ("email");



CREATE INDEX "idx_contacts_email_search_status" ON "public"."contacts" USING "btree" ("email_search_status");



CREATE INDEX "idx_contacts_email_validation_response" ON "public"."contacts" USING "gin" ("email_validation_response");



CREATE INDEX "idx_contacts_firstname" ON "public"."contacts" USING "btree" ("firstname");



CREATE INDEX "idx_contacts_headline" ON "public"."contacts" USING "btree" ("headline");



CREATE INDEX "idx_contacts_hunter_email_requested" ON "public"."contacts" USING "btree" ("organization_id", "hunter_email_requested") WHERE ("hunter_email_requested" = false);



CREATE INDEX "idx_contacts_hunter_email_response" ON "public"."contacts" USING "gin" ("hunter_email_response");



CREATE INDEX "idx_contacts_icypeas_email_requested" ON "public"."contacts" USING "btree" ("organization_id", "icypeas_email_requested") WHERE ("icypeas_email_requested" = false);



CREATE INDEX "idx_contacts_icypeas_email_response" ON "public"."contacts" USING "gin" ("icypeas_email_response");



CREATE INDEX "idx_contacts_languages_gin" ON "public"."contacts" USING "gin" ("languages");



CREATE INDEX "idx_contacts_last_incoming_email_at" ON "public"."contacts" USING "btree" ("last_incoming_email_at");



CREATE INDEX "idx_contacts_lastname" ON "public"."contacts" USING "btree" ("lastname");



CREATE INDEX "idx_contacts_linkedin_url" ON "public"."contacts" USING "btree" ("linkedin_url");



CREATE INDEX "idx_contacts_location" ON "public"."contacts" USING "btree" ("location");



CREATE INDEX "idx_contacts_location_gin" ON "public"."contacts" USING "gin" ("location");



CREATE INDEX "idx_contacts_ooo_until" ON "public"."contacts" USING "btree" ("ooo_until");



CREATE INDEX "idx_contacts_org_id" ON "public"."contacts" USING "btree" ("organization_id");



CREATE INDEX "idx_contacts_organization_id" ON "public"."contacts" USING "btree" ("organization_id");



CREATE INDEX "idx_contacts_pipeline_stage" ON "public"."contacts" USING "btree" ("pipeline_stage");



CREATE INDEX "idx_contacts_provider_responses" ON "public"."contacts" USING "gin" ("provider_responses");



CREATE INDEX "idx_contacts_sales_brief" ON "public"."contacts" USING "btree" ("sales_brief") WHERE ("sales_brief" IS NOT NULL);



CREATE INDEX "idx_contacts_search_gin" ON "public"."contacts" USING "gin" ("name" "public"."gin_trgm_ops", "email" "public"."gin_trgm_ops", "firstname" "public"."gin_trgm_ops", "lastname" "public"."gin_trgm_ops", "headline" "public"."gin_trgm_ops");



CREATE INDEX "idx_contacts_skills_gin" ON "public"."contacts" USING "gin" ("skills");



CREATE INDEX "idx_contacts_stop_drafts" ON "public"."contacts" USING "btree" ("stop_drafts");



CREATE INDEX "idx_contacts_unsubscribed_at" ON "public"."contacts" USING "btree" ("unsubscribed_at");



CREATE INDEX "idx_conversation_messages_conversation_id" ON "public"."conversation_messages" USING "btree" ("conversation_id");



CREATE INDEX "idx_conversation_messages_organization_id" ON "public"."conversation_messages" USING "btree" ("organization_id");



CREATE INDEX "idx_conversation_messages_sender_type" ON "public"."conversation_messages" USING "btree" ("sender_type");



CREATE INDEX "idx_conversation_messages_sent_at" ON "public"."conversation_messages" USING "btree" ("sent_at");



CREATE INDEX "idx_conversations_contact_id" ON "public"."conversations" USING "btree" ("contact_id");



CREATE INDEX "idx_conversations_is_unread" ON "public"."conversations" USING "btree" ("is_unread");



CREATE INDEX "idx_conversations_last_message_at" ON "public"."conversations" USING "btree" ("last_message_at");



CREATE INDEX "idx_conversations_organization_id" ON "public"."conversations" USING "btree" ("organization_id");



CREATE INDEX "idx_conversations_status" ON "public"."conversations" USING "btree" ("status");



CREATE INDEX "idx_icp_linkedin_org_type" ON "public"."organization_icp_linkedin_urls" USING "btree" ("organization_id", "url_type");



CREATE INDEX "idx_icp_linkedin_url" ON "public"."organization_icp_linkedin_urls" USING "btree" ("url");



CREATE INDEX "idx_icp_profiles_created_at" ON "public"."icp_profiles" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_icp_profiles_organization_default" ON "public"."icp_profiles" USING "btree" ("organization_id", "is_default") WHERE ("is_default" = true);



CREATE INDEX "idx_icp_profiles_organization_id" ON "public"."icp_profiles" USING "btree" ("organization_id");



CREATE INDEX "idx_interviewer_org_id" ON "public"."interviewer" USING "btree" ("organization_id");



CREATE INDEX "idx_organization_deleted" ON "public"."organization" USING "btree" ("deleted");



CREATE INDEX "idx_organization_files_category" ON "public"."organization_files" USING "btree" ("file_category");



CREATE INDEX "idx_organization_files_created_at" ON "public"."organization_files" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_organization_files_has_sensitive_data" ON "public"."organization_files" USING "btree" ("organization_id", "has_sensitive_data") WHERE ("has_sensitive_data" = true);



CREATE INDEX "idx_organization_files_industries" ON "public"."organization_files" USING "gin" ("industries") WHERE ("file_category" = 'case_study'::"public"."file_category_enum");



CREATE INDEX "idx_organization_files_org_id" ON "public"."organization_files" USING "btree" ("organization_id");



CREATE INDEX "idx_organization_files_processing_status" ON "public"."organization_files" USING "btree" ("processing_status");



CREATE INDEX "idx_organization_files_shared" ON "public"."organization_files" USING "btree" ("shared_with_client");



CREATE INDEX "idx_organization_icp_linkedin_urls_organization_id" ON "public"."organization_icp_linkedin_urls" USING "btree" ("organization_id");



CREATE INDEX "idx_organization_settings_api_credentials" ON "public"."organization_settings" USING "gin" ("api_credentials");



CREATE INDEX "idx_organization_settings_api_key" ON "public"."organization_settings" USING "btree" ("api_key") WHERE ("api_key" IS NOT NULL);



CREATE INDEX "idx_organization_settings_onboarding" ON "public"."organization_settings" USING "btree" ("onboarding_completed");



CREATE INDEX "idx_organization_settings_onboarding_skipped" ON "public"."organization_settings" USING "btree" ("onboarding_skipped");



CREATE INDEX "idx_organization_settings_org_id" ON "public"."organization_settings" USING "btree" ("organization_id");



COMMENT ON INDEX "public"."idx_organization_settings_org_id" IS 'Fixes 100+ sequential scans on organization_settings table';



CREATE INDEX "idx_organization_settings_organization_id" ON "public"."organization_settings" USING "btree" ("organization_id");



CREATE INDEX "idx_short_urls_contact" ON "public"."document_short_urls" USING "btree" ("contact_id");



CREATE INDEX "idx_short_urls_expires_at" ON "public"."document_short_urls" USING "btree" ("expires_at");



CREATE INDEX "idx_short_urls_file_id" ON "public"."document_short_urls" USING "btree" ("file_id");



CREATE INDEX "idx_short_urls_organization" ON "public"."document_short_urls" USING "btree" ("organization_id");



CREATE INDEX "idx_short_urls_short_code" ON "public"."document_short_urls" USING "btree" ("short_code");



CREATE INDEX "idx_style_guidelines_organization_id" ON "public"."style_guidelines" USING "btree" ("organization_id");



CREATE INDEX "idx_system_config_key" ON "public"."system_config" USING "btree" ("key");



CREATE INDEX "idx_tasks_campaign_id" ON "public"."tasks" USING "btree" ("campaign_id");



CREATE INDEX "idx_tasks_campaign_verification" ON "public"."tasks" USING "btree" ("organization_id", "task_type", "status", "campaign_id") WHERE (("task_type" = 'company_verification'::"public"."task_type") AND ("status" = 'pending'::"public"."task_status"));



CREATE INDEX "idx_tasks_company_id" ON "public"."tasks" USING "btree" ("company_id");



CREATE INDEX "idx_tasks_company_id_created_at" ON "public"."tasks" USING "btree" ("company_id", "created_at" DESC);



CREATE INDEX "idx_tasks_company_verification" ON "public"."tasks" USING "btree" ("company_id", "task_type", "created_at") WHERE ("task_type" = 'company_verification'::"public"."task_type");



CREATE INDEX "idx_tasks_contact_id" ON "public"."tasks" USING "btree" ("contact_id");



CREATE INDEX "idx_tasks_contact_id_organization_id" ON "public"."tasks" USING "btree" ("contact_id", "organization_id") WHERE ("contact_id" IS NOT NULL);



CREATE INDEX "idx_tasks_conversation_summary_text_search" ON "public"."tasks" USING "gin" ("to_tsvector"('"english"'::"regconfig", "conversation_summary_text"));



CREATE INDEX "idx_tasks_conversation_summary_thread_id" ON "public"."tasks" USING "gin" ((("conversation_summary" -> 'thread_id'::"text")));



CREATE INDEX "idx_tasks_created_by_user_id" ON "public"."tasks" USING "btree" ("created_by_user_id");



CREATE INDEX "idx_tasks_due_date" ON "public"."tasks" USING "btree" ("due_date");



CREATE INDEX "idx_tasks_email_id" ON "public"."tasks" USING "btree" ("email_id");



CREATE INDEX "idx_tasks_feedback" ON "public"."tasks" USING "btree" ("feedback") WHERE ("feedback" IS NOT NULL);



CREATE INDEX "idx_tasks_generation_log" ON "public"."tasks" USING "gin" ("generation_log");



CREATE INDEX "idx_tasks_org_completed" ON "public"."tasks" USING "btree" ("organization_id", "completed_at") WHERE ("completed_at" IS NOT NULL);



CREATE INDEX "idx_tasks_org_created" ON "public"."tasks" USING "btree" ("organization_id", "created_at");



CREATE INDEX "idx_tasks_org_due_date" ON "public"."tasks" USING "btree" ("organization_id", "due_date") WHERE ("due_date" IS NOT NULL);



CREATE INDEX "idx_tasks_org_status" ON "public"."tasks" USING "btree" ("organization_id", "status");



COMMENT ON INDEX "public"."idx_tasks_org_status" IS 'Optimizes task queries filtering by organization and status';



CREATE INDEX "idx_tasks_org_status_created" ON "public"."tasks" USING "btree" ("organization_id", "status", "created_at" DESC);



CREATE INDEX "idx_tasks_org_status_priority_created" ON "public"."tasks" USING "btree" ("organization_id", "status", "priority_rank", "created_at" DESC);



CREATE INDEX "idx_tasks_org_type_status" ON "public"."tasks" USING "btree" ("organization_id", "task_type", "status");



CREATE INDEX "idx_tasks_organization_id" ON "public"."tasks" USING "btree" ("organization_id");



CREATE INDEX "idx_tasks_priority_rank" ON "public"."tasks" USING "btree" ("priority_rank");



CREATE UNIQUE INDEX "idx_tasks_processing_unique_contact" ON "public"."tasks" USING "btree" ("contact_id", "organization_id") WHERE (("task_type" = 'email_generation_processing'::"public"."task_type") AND ("status" = ANY (ARRAY['pending'::"public"."task_status", 'in_progress'::"public"."task_status"])));



COMMENT ON INDEX "public"."idx_tasks_processing_unique_contact" IS 'Ensures only one active email_generation_processing task can exist per contact at a time, preventing race conditions in webhook processing';



CREATE UNIQUE INDEX "idx_tasks_review_draft_unique_first_email" ON "public"."tasks" USING "btree" ("contact_id", "organization_id") WHERE (("task_type" = 'review_draft'::"public"."task_type") AND ("status" = 'pending'::"public"."task_status") AND ("thread_id" IS NULL));



COMMENT ON INDEX "public"."idx_tasks_review_draft_unique_first_email" IS 'Ensures only one pending first-email review_draft task can exist per contact at a time. Does not apply to replies (tasks with thread_id) to allow multiple reply drafts. Prevents race conditions in webhook and contact extraction processing.';



CREATE INDEX "idx_tasks_scheduled" ON "public"."tasks" USING "btree" ("organization_id", "scheduled") WHERE ("scheduled" = true);



CREATE INDEX "idx_tasks_send_status" ON "public"."tasks" USING "btree" ("organization_id", "send_status") WHERE ("send_status" IS NOT NULL);



CREATE INDEX "idx_tasks_send_status_failed" ON "public"."tasks" USING "btree" ("organization_id", "send_status", "updated_at") WHERE ("send_status" = 'sent_failed'::"text");



CREATE INDEX "idx_tasks_sent_at" ON "public"."tasks" USING "btree" ("organization_id", "sent_at") WHERE ("sent_at" IS NOT NULL);



CREATE INDEX "idx_tasks_status" ON "public"."tasks" USING "btree" ("status");



CREATE INDEX "idx_tasks_subject" ON "public"."tasks" USING "btree" ("organization_id", "subject") WHERE ("subject" IS NOT NULL);



CREATE INDEX "idx_tasks_task_type" ON "public"."tasks" USING "btree" ("task_type");



CREATE INDEX "idx_tasks_thread_id" ON "public"."tasks" USING "btree" ("thread_id");



CREATE INDEX "idx_tasks_unanswered_questions" ON "public"."tasks" USING "gin" ((("conversation_summary" -> 'unanswered_questions'::"text")));



CREATE INDEX "idx_tasks_verification_no_campaign" ON "public"."tasks" USING "btree" ("organization_id", "task_type", "status", "company_id") WHERE (("task_type" = 'company_verification'::"public"."task_type") AND ("status" = 'pending'::"public"."task_status") AND ("campaign_id" IS NULL));



CREATE INDEX "idx_token_usage_created" ON "public"."token_usage" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_token_usage_org_session" ON "public"."token_usage" USING "btree" ("organization_id", "session_id");



CREATE INDEX "idx_token_usage_provider" ON "public"."token_usage" USING "btree" ("provider");



CREATE INDEX "idx_usage_campaign_id" ON "public"."usage" USING "btree" ("campaign_id");



CREATE INDEX "idx_usage_context" ON "public"."usage" USING "btree" ("organization_id", "usage_context", "created_at" DESC);



CREATE INDEX "idx_usage_cost" ON "public"."usage" USING "btree" ("organization_id", "original_cost", "sellton_cost");



CREATE INDEX "idx_usage_created" ON "public"."usage" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_usage_created_at_date" ON "public"."usage" USING "btree" ("organization_id", "date"(("created_at" AT TIME ZONE 'UTC'::"text")));



CREATE INDEX "idx_usage_org_campaign" ON "public"."usage" USING "btree" ("organization_id", "campaign_id") WHERE ("campaign_id" IS NOT NULL);



CREATE INDEX "idx_usage_org_costs" ON "public"."usage" USING "btree" ("organization_id", "sellton_cost", "original_cost") WHERE (("sellton_cost" > (0)::numeric) OR ("original_cost" > (0)::numeric));



CREATE INDEX "idx_usage_org_created" ON "public"."usage" USING "btree" ("organization_id", "created_at" DESC);



COMMENT ON INDEX "public"."idx_usage_org_created" IS 'Optimizes usage analytics queries by organization and date';



CREATE INDEX "idx_usage_org_created_desc" ON "public"."usage" USING "btree" ("organization_id", "created_at" DESC);



CREATE INDEX "idx_usage_org_provider" ON "public"."usage" USING "btree" ("organization_id", "provider");



CREATE INDEX "idx_usage_org_session" ON "public"."usage" USING "btree" ("organization_id", "session_id");



CREATE INDEX "idx_usage_pricing" ON "public"."usage" USING "gin" ("original_pricing", "sellton_pricing");



CREATE INDEX "idx_usage_provider" ON "public"."usage" USING "btree" ("provider");



CREATE INDEX "idx_usage_summary_org_date" ON "public"."usage_summary" USING "btree" ("organization_id", "date" DESC);



CREATE INDEX "idx_usage_summary_provider" ON "public"."usage_summary" USING "btree" ("provider");



CREATE INDEX "idx_user_organizations_organization_id" ON "public"."user_organizations" USING "btree" ("organization_id");



CREATE INDEX "idx_user_organizations_user_id" ON "public"."user_organizations" USING "btree" ("user_id");



CREATE INDEX "interview_organization_id_idx" ON "public"."interview" USING "btree" ("organization_id");



CREATE INDEX "interviewer_organization_id_idx" ON "public"."interviewer" USING "btree" ("organization_id");



CREATE INDEX "response_organization_id_idx" ON "public"."response" USING "btree" ("organization_id");



CREATE INDEX "style_guidelines_organization_id_idx" ON "public"."style_guidelines" USING "btree" ("organization_id");



CREATE UNIQUE INDEX "style_guidelines_organization_unique" ON "public"."style_guidelines" USING "btree" ("organization_id");



CREATE INDEX "user_organizations_organization_id_idx" ON "public"."user_organizations" USING "btree" ("organization_id");



CREATE INDEX "user_organizations_user_id_idx" ON "public"."user_organizations" USING "btree" ("user_id");



CREATE OR REPLACE TRIGGER "trg_log_file_upload" AFTER INSERT ON "public"."organization_files" FOR EACH ROW EXECUTE FUNCTION "public"."log_file_upload"();



CREATE OR REPLACE TRIGGER "trg_on_file_delete_update_companies" AFTER DELETE ON "public"."organization_files" FOR EACH ROW EXECUTE FUNCTION "public"."remove_deleted_file_from_companies"();



CREATE OR REPLACE TRIGGER "trigger_create_email_status_activity" AFTER INSERT OR UPDATE OF "status" ON "public"."campaign_emails" FOR EACH ROW EXECUTE FUNCTION "public"."create_email_status_activity"();



CREATE OR REPLACE TRIGGER "trigger_set_task_priority_rank" BEFORE INSERT OR UPDATE OF "priority" ON "public"."tasks" FOR EACH ROW EXECUTE FUNCTION "public"."set_task_priority_rank"();



CREATE OR REPLACE TRIGGER "trigger_update_selected_company_ids" BEFORE INSERT OR UPDATE OF "curated_companies" ON "public"."campaigns" FOR EACH ROW EXECUTE FUNCTION "public"."update_selected_company_ids"();



CREATE OR REPLACE TRIGGER "update_campaign_companies_updated_at" BEFORE UPDATE ON "public"."campaign_companies" FOR EACH ROW EXECUTE FUNCTION "public"."update_campaign_companies_updated_at"();



CREATE OR REPLACE TRIGGER "update_campaign_emails_updated_at" BEFORE UPDATE ON "public"."campaign_emails" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_campaigns_updated_at" BEFORE UPDATE ON "public"."campaigns" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_companies_updated_at" BEFORE UPDATE ON "public"."companies" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_company_activities_updated_at" BEFORE UPDATE ON "public"."company_activities" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_company_blocked_status_trigger" BEFORE INSERT OR UPDATE OF "icp_score" ON "public"."companies" FOR EACH ROW EXECUTE FUNCTION "public"."update_company_blocked_status"();



COMMENT ON TRIGGER "update_company_blocked_status_trigger" ON "public"."companies" IS 'Automatically sets blocked_by_icp based on icp_score.blocked flag';



CREATE OR REPLACE TRIGGER "update_company_contacts_updated_at" BEFORE UPDATE ON "public"."company_contacts" FOR EACH ROW EXECUTE FUNCTION "public"."update_company_contacts_updated_at"();



CREATE OR REPLACE TRIGGER "update_contact_activities_updated_at" BEFORE UPDATE ON "public"."contact_activities" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_contact_channels_updated_at" BEFORE UPDATE ON "public"."contact_channels" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_contact_notes_updated_at" BEFORE UPDATE ON "public"."contact_notes" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_contacts_updated_at" BEFORE UPDATE ON "public"."contacts" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_conversation_messages_updated_at" BEFORE UPDATE ON "public"."conversation_messages" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_conversations_updated_at" BEFORE UPDATE ON "public"."conversations" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_icp_profiles_updated_at" BEFORE UPDATE ON "public"."icp_profiles" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_organization_files_updated_at" BEFORE UPDATE ON "public"."organization_files" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_organization_settings_updated_at_trigger" BEFORE UPDATE ON "public"."organization_settings" FOR EACH ROW EXECUTE FUNCTION "public"."update_organization_settings_updated_at"();



CREATE OR REPLACE TRIGGER "update_style_guidelines_updated_at" BEFORE UPDATE ON "public"."style_guidelines" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_system_config_updated_at_trigger" BEFORE UPDATE ON "public"."system_config" FOR EACH ROW EXECUTE FUNCTION "public"."update_system_config_updated_at"();



CREATE OR REPLACE TRIGGER "update_tasks_updated_at" BEFORE UPDATE ON "public"."tasks" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_usage_summary_trigger" AFTER INSERT ON "public"."usage" FOR EACH ROW EXECUTE FUNCTION "public"."update_usage_summary"();



CREATE OR REPLACE TRIGGER "validate_task_contact_on_insert" BEFORE INSERT ON "public"."tasks" FOR EACH ROW EXECUTE FUNCTION "public"."validate_task_contact"();



CREATE OR REPLACE TRIGGER "validate_task_contact_on_update" BEFORE UPDATE ON "public"."tasks" FOR EACH ROW WHEN (("new"."contact_id" IS DISTINCT FROM "old"."contact_id")) EXECUTE FUNCTION "public"."validate_task_contact"();



ALTER TABLE ONLY "public"."campaign_activities"
    ADD CONSTRAINT "campaign_activities_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaign_activities"
    ADD CONSTRAINT "campaign_activities_contact_id_fkey" FOREIGN KEY ("contact_id") REFERENCES "public"."contacts"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."campaign_activities"
    ADD CONSTRAINT "campaign_activities_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organization"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaign_companies"
    ADD CONSTRAINT "campaign_companies_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaign_companies"
    ADD CONSTRAINT "campaign_companies_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaign_companies"
    ADD CONSTRAINT "campaign_companies_icp_profile_id_used_fkey" FOREIGN KEY ("icp_profile_id_used") REFERENCES "public"."icp_profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."campaign_companies"
    ADD CONSTRAINT "campaign_companies_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organization"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaign_emails"
    ADD CONSTRAINT "campaign_emails_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaign_emails"
    ADD CONSTRAINT "campaign_emails_contact_id_fkey" FOREIGN KEY ("contact_id") REFERENCES "public"."contacts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaign_emails"
    ADD CONSTRAINT "campaign_emails_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organization"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaign_files"
    ADD CONSTRAINT "campaign_files_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaign_files"
    ADD CONSTRAINT "campaign_files_file_id_fkey" FOREIGN KEY ("file_id") REFERENCES "public"."organization_files"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaign_seed_companies"
    ADD CONSTRAINT "campaign_seed_companies_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaign_seed_companies"
    ADD CONSTRAINT "campaign_seed_companies_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organization"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaigns"
    ADD CONSTRAINT "campaigns_icp_profile_id_fkey" FOREIGN KEY ("icp_profile_id") REFERENCES "public"."icp_profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."campaigns"
    ADD CONSTRAINT "campaigns_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organization"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."companies"
    ADD CONSTRAINT "companies_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organization"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."company_activities"
    ADD CONSTRAINT "company_activities_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."company_activities"
    ADD CONSTRAINT "company_activities_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."company_activities"
    ADD CONSTRAINT "company_activities_contact_id_fkey" FOREIGN KEY ("contact_id") REFERENCES "public"."contacts"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."company_activities"
    ADD CONSTRAINT "company_activities_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organization"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."company_activities"
    ADD CONSTRAINT "company_activities_task_id_fkey" FOREIGN KEY ("task_id") REFERENCES "public"."tasks"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."company_contacts"
    ADD CONSTRAINT "company_contacts_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."company_contacts"
    ADD CONSTRAINT "company_contacts_contact_id_fkey" FOREIGN KEY ("contact_id") REFERENCES "public"."contacts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."company_contacts"
    ADD CONSTRAINT "company_contacts_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organization"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."contact_activities"
    ADD CONSTRAINT "contact_activities_contact_id_fkey" FOREIGN KEY ("contact_id") REFERENCES "public"."contacts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."contact_activities"
    ADD CONSTRAINT "contact_activities_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organization"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."contact_activities"
    ADD CONSTRAINT "contact_activities_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."contact_channels"
    ADD CONSTRAINT "contact_channels_contact_id_fkey" FOREIGN KEY ("contact_id") REFERENCES "public"."contacts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."contact_channels"
    ADD CONSTRAINT "contact_channels_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organization"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."contact_notes"
    ADD CONSTRAINT "contact_notes_contact_id_fkey" FOREIGN KEY ("contact_id") REFERENCES "public"."contacts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."contact_notes"
    ADD CONSTRAINT "contact_notes_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organization"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."contact_notes"
    ADD CONSTRAINT "contact_notes_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."contacts"
    ADD CONSTRAINT "contacts_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organization"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."conversation_messages"
    ADD CONSTRAINT "conversation_messages_conversation_id_fkey" FOREIGN KEY ("conversation_id") REFERENCES "public"."conversations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."conversation_messages"
    ADD CONSTRAINT "conversation_messages_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organization"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."conversation_messages"
    ADD CONSTRAINT "conversation_messages_sender_user_id_fkey" FOREIGN KEY ("sender_user_id") REFERENCES "public"."user"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."conversations"
    ADD CONSTRAINT "conversations_contact_id_fkey" FOREIGN KEY ("contact_id") REFERENCES "public"."contacts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."conversations"
    ADD CONSTRAINT "conversations_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organization"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."conversations"
    ADD CONSTRAINT "conversations_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."feedback"
    ADD CONSTRAINT "feedback_interview_id_fkey" FOREIGN KEY ("interview_id") REFERENCES "public"."interview"("id");



ALTER TABLE ONLY "public"."feedback"
    ADD CONSTRAINT "feedback_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organization"("id");



ALTER TABLE ONLY "public"."document_short_urls"
    ADD CONSTRAINT "fk_contact" FOREIGN KEY ("contact_id") REFERENCES "public"."contacts"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."document_access_events"
    ADD CONSTRAINT "fk_contact_event" FOREIGN KEY ("contact_id") REFERENCES "public"."contacts"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."document_short_urls"
    ADD CONSTRAINT "fk_organization" FOREIGN KEY ("organization_id") REFERENCES "public"."organization"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."document_access_events"
    ADD CONSTRAINT "fk_short_url" FOREIGN KEY ("short_url_id") REFERENCES "public"."document_short_urls"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."icp_profiles"
    ADD CONSTRAINT "icp_profiles_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organization"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."interview"
    ADD CONSTRAINT "interview_interviewer_id_fkey" FOREIGN KEY ("interviewer_id") REFERENCES "public"."interviewer"("id");



ALTER TABLE ONLY "public"."interview"
    ADD CONSTRAINT "interview_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organization"("id");



ALTER TABLE ONLY "public"."interview"
    ADD CONSTRAINT "interview_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id");



ALTER TABLE ONLY "public"."interviewer"
    ADD CONSTRAINT "interviewer_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organization"("id");



ALTER TABLE ONLY "public"."organization_files"
    ADD CONSTRAINT "organization_files_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organization"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."organization_icp_linkedin_urls"
    ADD CONSTRAINT "organization_icp_linkedin_urls_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organization"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."organization_settings"
    ADD CONSTRAINT "organization_settings_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organization"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."response"
    ADD CONSTRAINT "response_interview_id_fkey" FOREIGN KEY ("interview_id") REFERENCES "public"."interview"("id");



ALTER TABLE ONLY "public"."response"
    ADD CONSTRAINT "response_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organization"("id");



ALTER TABLE ONLY "public"."style_guidelines"
    ADD CONSTRAINT "style_guidelines_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organization"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."tasks"
    ADD CONSTRAINT "tasks_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."tasks"
    ADD CONSTRAINT "tasks_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."tasks"
    ADD CONSTRAINT "tasks_contact_id_fkey" FOREIGN KEY ("contact_id") REFERENCES "public"."contacts"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."tasks"
    ADD CONSTRAINT "tasks_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organization"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_organizations"
    ADD CONSTRAINT "user_organizations_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organization"("id");



ALTER TABLE ONLY "public"."user_organizations"
    ADD CONSTRAINT "user_organizations_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id");



CREATE POLICY "Allow all operations on usage" ON "public"."usage" USING (true);



CREATE POLICY "Allow all operations on usage_summary" ON "public"."usage_summary" USING (true);



CREATE POLICY "No direct access to organization_settings" ON "public"."organization_settings" USING (false) WITH CHECK (false);



CREATE POLICY "Organizations can insert their own token usage" ON "public"."token_usage" FOR INSERT WITH CHECK (("organization_id" = "current_setting"('app.current_organization_id'::"text", true)));



CREATE POLICY "Organizations can view their own token usage" ON "public"."token_usage" FOR SELECT USING (("organization_id" = "current_setting"('app.current_organization_id'::"text", true)));



CREATE POLICY "Service role has full access to access events" ON "public"."document_access_events" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "Service role has full access to short URLs" ON "public"."document_short_urls" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "Users can create campaigns in their organization" ON "public"."campaigns" FOR INSERT WITH CHECK (("organization_id" IN ( SELECT "user_organizations"."organization_id"
   FROM "public"."user_organizations"
  WHERE ("user_organizations"."user_id" = ("auth"."uid"())::"text"))));



CREATE POLICY "Users can create contacts in their organization" ON "public"."contacts" FOR INSERT WITH CHECK (("organization_id" IN ( SELECT "user_organizations"."organization_id"
   FROM "public"."user_organizations"
  WHERE ("user_organizations"."user_id" = ("auth"."uid"())::"text"))));



CREATE POLICY "Users can delete campaign companies for their organization" ON "public"."campaign_companies" FOR DELETE USING (("organization_id" = ("auth"."jwt"() ->> 'organization_id'::"text")));



CREATE POLICY "Users can delete campaign files for their organization" ON "public"."campaign_files" FOR DELETE USING ((EXISTS ( SELECT 1
   FROM "public"."campaigns" "c"
  WHERE (("c"."id" = "campaign_files"."campaign_id") AND ("c"."organization_id" IN ( SELECT "user_organizations"."organization_id"
           FROM "public"."user_organizations"
          WHERE ("user_organizations"."user_id" = ("auth"."uid"())::"text")))))));



CREATE POLICY "Users can delete campaigns in their organization" ON "public"."campaigns" FOR DELETE USING (("organization_id" IN ( SELECT "user_organizations"."organization_id"
   FROM "public"."user_organizations"
  WHERE ("user_organizations"."user_id" = ("auth"."uid"())::"text"))));



CREATE POLICY "Users can delete contacts in their organization" ON "public"."contacts" FOR DELETE USING (("organization_id" IN ( SELECT "user_organizations"."organization_id"
   FROM "public"."user_organizations"
  WHERE ("user_organizations"."user_id" = ("auth"."uid"())::"text"))));



CREATE POLICY "Users can delete their organization's ICP profiles" ON "public"."icp_profiles" FOR DELETE USING (("organization_id" IN ( SELECT "organization"."id"
   FROM "public"."organization"
  WHERE ("organization"."id" = "icp_profiles"."organization_id"))));



CREATE POLICY "Users can delete their organization's LinkedIn URLs" ON "public"."organization_icp_linkedin_urls" FOR DELETE USING (("organization_id" IN ( SELECT "user_organizations"."organization_id"
   FROM "public"."user_organizations"
  WHERE ("user_organizations"."user_id" = ("auth"."uid"())::"text"))));



CREATE POLICY "Users can delete their organization's files" ON "public"."organization_files" FOR DELETE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can delete their own company activities" ON "public"."company_activities" FOR DELETE USING ((("organization_id" = "current_setting"('app.current_organization_id'::"text", true)) AND ("created_by_user_id" = "current_setting"('app.current_user_id'::"text", true))));



CREATE POLICY "Users can insert ICP profiles for their organization" ON "public"."icp_profiles" FOR INSERT WITH CHECK (("organization_id" IN ( SELECT "organization"."id"
   FROM "public"."organization"
  WHERE ("organization"."id" = "icp_profiles"."organization_id"))));



CREATE POLICY "Users can insert LinkedIn URLs for their organization" ON "public"."organization_icp_linkedin_urls" FOR INSERT WITH CHECK (("organization_id" IN ( SELECT "user_organizations"."organization_id"
   FROM "public"."user_organizations"
  WHERE ("user_organizations"."user_id" = ("auth"."uid"())::"text"))));



CREATE POLICY "Users can insert campaign companies for their organization" ON "public"."campaign_companies" FOR INSERT WITH CHECK (("organization_id" = ("auth"."jwt"() ->> 'organization_id'::"text")));



CREATE POLICY "Users can insert campaign files for their organization" ON "public"."campaign_files" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."campaigns" "c"
  WHERE (("c"."id" = "campaign_files"."campaign_id") AND ("c"."organization_id" IN ( SELECT "user_organizations"."organization_id"
           FROM "public"."user_organizations"
          WHERE ("user_organizations"."user_id" = ("auth"."uid"())::"text")))))));



CREATE POLICY "Users can insert company activities for their organization" ON "public"."company_activities" FOR INSERT WITH CHECK (("organization_id" = "current_setting"('app.current_organization_id'::"text", true)));



CREATE POLICY "Users can insert files for their organization" ON "public"."organization_files" FOR INSERT WITH CHECK (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can manage campaign activities in their organization" ON "public"."campaign_activities" USING (("organization_id" IN ( SELECT "user_organizations"."organization_id"
   FROM "public"."user_organizations"
  WHERE ("user_organizations"."user_id" = ("auth"."uid"())::"text"))));



CREATE POLICY "Users can manage campaign emails in their organization" ON "public"."campaign_emails" USING (("organization_id" IN ( SELECT "user_organizations"."organization_id"
   FROM "public"."user_organizations"
  WHERE ("user_organizations"."user_id" = ("auth"."uid"())::"text"))));



CREATE POLICY "Users can manage companies in their organization" ON "public"."companies" USING (("organization_id" IN ( SELECT "user_organizations"."organization_id"
   FROM "public"."user_organizations"
  WHERE ("user_organizations"."user_id" = ("auth"."uid"())::"text"))));



CREATE POLICY "Users can manage contact activities in their organization" ON "public"."contact_activities" USING (("organization_id" IN ( SELECT "user_organizations"."organization_id"
   FROM "public"."user_organizations"
  WHERE ("user_organizations"."user_id" = ("auth"."uid"())::"text"))));



CREATE POLICY "Users can manage contact channels in their organization" ON "public"."contact_channels" USING (("organization_id" IN ( SELECT "user_organizations"."organization_id"
   FROM "public"."user_organizations"
  WHERE ("user_organizations"."user_id" = ("auth"."uid"())::"text"))));



CREATE POLICY "Users can manage contact notes in their organization" ON "public"."contact_notes" USING (("organization_id" IN ( SELECT "user_organizations"."organization_id"
   FROM "public"."user_organizations"
  WHERE ("user_organizations"."user_id" = ("auth"."uid"())::"text"))));



CREATE POLICY "Users can manage conversation messages in their organization" ON "public"."conversation_messages" USING (("organization_id" IN ( SELECT "user_organizations"."organization_id"
   FROM "public"."user_organizations"
  WHERE ("user_organizations"."user_id" = ("auth"."uid"())::"text"))));



CREATE POLICY "Users can manage conversations in their organization" ON "public"."conversations" USING (("organization_id" IN ( SELECT "user_organizations"."organization_id"
   FROM "public"."user_organizations"
  WHERE ("user_organizations"."user_id" = ("auth"."uid"())::"text"))));



CREATE POLICY "Users can manage tasks in their organization" ON "public"."tasks" USING (("organization_id" IN ( SELECT "user_organizations"."organization_id"
   FROM "public"."user_organizations"
  WHERE ("user_organizations"."user_id" = ("auth"."uid"())::"text"))));



CREATE POLICY "Users can update campaign companies for their organization" ON "public"."campaign_companies" FOR UPDATE USING (("organization_id" = ("auth"."jwt"() ->> 'organization_id'::"text")));



CREATE POLICY "Users can update campaigns in their organization" ON "public"."campaigns" FOR UPDATE USING (("organization_id" IN ( SELECT "user_organizations"."organization_id"
   FROM "public"."user_organizations"
  WHERE ("user_organizations"."user_id" = ("auth"."uid"())::"text"))));



CREATE POLICY "Users can update contacts in their organization" ON "public"."contacts" FOR UPDATE USING (("organization_id" IN ( SELECT "user_organizations"."organization_id"
   FROM "public"."user_organizations"
  WHERE ("user_organizations"."user_id" = ("auth"."uid"())::"text"))));



CREATE POLICY "Users can update their organization's ICP profiles" ON "public"."icp_profiles" FOR UPDATE USING (("organization_id" IN ( SELECT "organization"."id"
   FROM "public"."organization"
  WHERE ("organization"."id" = "icp_profiles"."organization_id"))));



CREATE POLICY "Users can update their organization's LinkedIn URLs" ON "public"."organization_icp_linkedin_urls" FOR UPDATE USING (("organization_id" IN ( SELECT "user_organizations"."organization_id"
   FROM "public"."user_organizations"
  WHERE ("user_organizations"."user_id" = ("auth"."uid"())::"text"))));



CREATE POLICY "Users can update their organization's files" ON "public"."organization_files" FOR UPDATE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can update their own company activities" ON "public"."company_activities" FOR UPDATE USING ((("organization_id" = "current_setting"('app.current_organization_id'::"text", true)) AND ("created_by_user_id" = "current_setting"('app.current_user_id'::"text", true))));



CREATE POLICY "Users can view access events for their organization" ON "public"."document_access_events" FOR SELECT USING (("organization_id" IN ( SELECT "organization"."id"
   FROM "public"."organization"
  WHERE ("organization"."id" = "document_access_events"."organization_id"))));



CREATE POLICY "Users can view campaign activities in their organization" ON "public"."campaign_activities" FOR SELECT USING (("organization_id" IN ( SELECT "user_organizations"."organization_id"
   FROM "public"."user_organizations"
  WHERE ("user_organizations"."user_id" = ("auth"."uid"())::"text"))));



CREATE POLICY "Users can view campaign companies for their organization" ON "public"."campaign_companies" FOR SELECT USING (("organization_id" = ("auth"."jwt"() ->> 'organization_id'::"text")));



CREATE POLICY "Users can view campaign emails in their organization" ON "public"."campaign_emails" FOR SELECT USING (("organization_id" IN ( SELECT "user_organizations"."organization_id"
   FROM "public"."user_organizations"
  WHERE ("user_organizations"."user_id" = ("auth"."uid"())::"text"))));



CREATE POLICY "Users can view campaign files for their organization" ON "public"."campaign_files" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."campaigns" "c"
  WHERE (("c"."id" = "campaign_files"."campaign_id") AND ("c"."organization_id" IN ( SELECT "user_organizations"."organization_id"
           FROM "public"."user_organizations"
          WHERE ("user_organizations"."user_id" = ("auth"."uid"())::"text")))))));



CREATE POLICY "Users can view campaigns in their organization" ON "public"."campaigns" FOR SELECT USING (("organization_id" IN ( SELECT "user_organizations"."organization_id"
   FROM "public"."user_organizations"
  WHERE ("user_organizations"."user_id" = ("auth"."uid"())::"text"))));



CREATE POLICY "Users can view companies in their organization" ON "public"."companies" FOR SELECT USING (("organization_id" IN ( SELECT "user_organizations"."organization_id"
   FROM "public"."user_organizations"
  WHERE ("user_organizations"."user_id" = ("auth"."uid"())::"text"))));



CREATE POLICY "Users can view company activities for their organization" ON "public"."company_activities" FOR SELECT USING (("organization_id" = "current_setting"('app.current_organization_id'::"text", true)));



CREATE POLICY "Users can view contact activities in their organization" ON "public"."contact_activities" FOR SELECT USING (("organization_id" IN ( SELECT "user_organizations"."organization_id"
   FROM "public"."user_organizations"
  WHERE ("user_organizations"."user_id" = ("auth"."uid"())::"text"))));



CREATE POLICY "Users can view contact channels in their organization" ON "public"."contact_channels" FOR SELECT USING (("organization_id" IN ( SELECT "user_organizations"."organization_id"
   FROM "public"."user_organizations"
  WHERE ("user_organizations"."user_id" = ("auth"."uid"())::"text"))));



CREATE POLICY "Users can view contact notes in their organization" ON "public"."contact_notes" FOR SELECT USING (("organization_id" IN ( SELECT "user_organizations"."organization_id"
   FROM "public"."user_organizations"
  WHERE ("user_organizations"."user_id" = ("auth"."uid"())::"text"))));



CREATE POLICY "Users can view contacts in their organization" ON "public"."contacts" FOR SELECT USING (("organization_id" IN ( SELECT "user_organizations"."organization_id"
   FROM "public"."user_organizations"
  WHERE ("user_organizations"."user_id" = ("auth"."uid"())::"text"))));



CREATE POLICY "Users can view conversation messages in their organization" ON "public"."conversation_messages" FOR SELECT USING (("organization_id" IN ( SELECT "user_organizations"."organization_id"
   FROM "public"."user_organizations"
  WHERE ("user_organizations"."user_id" = ("auth"."uid"())::"text"))));



CREATE POLICY "Users can view conversations in their organization" ON "public"."conversations" FOR SELECT USING (("organization_id" IN ( SELECT "user_organizations"."organization_id"
   FROM "public"."user_organizations"
  WHERE ("user_organizations"."user_id" = ("auth"."uid"())::"text"))));



CREATE POLICY "Users can view short URLs for their organization" ON "public"."document_short_urls" FOR SELECT USING (("organization_id" IN ( SELECT "organization"."id"
   FROM "public"."organization"
  WHERE ("organization"."id" = "document_short_urls"."organization_id"))));



CREATE POLICY "Users can view tasks in their organization" ON "public"."tasks" FOR SELECT USING (("organization_id" IN ( SELECT "user_organizations"."organization_id"
   FROM "public"."user_organizations"
  WHERE ("user_organizations"."user_id" = ("auth"."uid"())::"text"))));



CREATE POLICY "Users can view their organization's ICP profiles" ON "public"."icp_profiles" FOR SELECT USING (("organization_id" IN ( SELECT "organization"."id"
   FROM "public"."organization"
  WHERE ("organization"."id" = "icp_profiles"."organization_id"))));



CREATE POLICY "Users can view their organization's LinkedIn URLs" ON "public"."organization_icp_linkedin_urls" FOR SELECT USING (("organization_id" IN ( SELECT "user_organizations"."organization_id"
   FROM "public"."user_organizations"
  WHERE ("user_organizations"."user_id" = ("auth"."uid"())::"text"))));



CREATE POLICY "Users can view their organization's files" ON "public"."organization_files" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



ALTER TABLE "public"."campaign_activities" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."campaign_companies" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."campaign_emails" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."campaign_files" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."campaigns" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."companies" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."company_activities" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."contact_activities" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."contact_channels" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."contact_notes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."contacts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."conversation_messages" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."conversations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."document_access_events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."document_short_urls" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."icp_profiles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."organization_files" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."organization_icp_linkedin_urls" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."organization_settings" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "service_role_all" ON "public"."system_config" USING (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "public"."system_config" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."tasks" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."token_usage" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."usage" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."usage_summary" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";






ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."campaigns";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."companies";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."contacts";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."tasks";



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_in"("cstring") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_in"("cstring") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_in"("cstring") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_in"("cstring") TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_out"("public"."gtrgm") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_out"("public"."gtrgm") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_out"("public"."gtrgm") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_out"("public"."gtrgm") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_in"("cstring", "oid", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_in"("cstring", "oid", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_in"("cstring", "oid", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_in"("cstring", "oid", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_out"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_out"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_out"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_out"("public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_recv"("internal", "oid", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_recv"("internal", "oid", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_recv"("internal", "oid", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_recv"("internal", "oid", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_send"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_send"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_send"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_send"("public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_typmod_in"("cstring"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_typmod_in"("cstring"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_typmod_in"("cstring"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_typmod_in"("cstring"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_in"("cstring", "oid", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_in"("cstring", "oid", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_in"("cstring", "oid", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_in"("cstring", "oid", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_out"("public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_out"("public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_out"("public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_out"("public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_recv"("internal", "oid", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_recv"("internal", "oid", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_recv"("internal", "oid", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_recv"("internal", "oid", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_send"("public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_send"("public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_send"("public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_send"("public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_typmod_in"("cstring"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_typmod_in"("cstring"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_typmod_in"("cstring"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_typmod_in"("cstring"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_in"("cstring", "oid", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_in"("cstring", "oid", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_in"("cstring", "oid", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_in"("cstring", "oid", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_out"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_out"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_out"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_out"("public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_recv"("internal", "oid", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_recv"("internal", "oid", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_recv"("internal", "oid", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_recv"("internal", "oid", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_send"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_send"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_send"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_send"("public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_typmod_in"("cstring"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_typmod_in"("cstring"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_typmod_in"("cstring"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_typmod_in"("cstring"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_halfvec"(real[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(real[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(real[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(real[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(real[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(real[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(real[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(real[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_vector"(real[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_vector"(real[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_vector"(real[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_vector"(real[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_halfvec"(double precision[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(double precision[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(double precision[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(double precision[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(double precision[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(double precision[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(double precision[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(double precision[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_vector"(double precision[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_vector"(double precision[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_vector"(double precision[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_vector"(double precision[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_halfvec"(integer[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(integer[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(integer[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(integer[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(integer[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(integer[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(integer[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(integer[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_vector"(integer[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_vector"(integer[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_vector"(integer[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_vector"(integer[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_halfvec"(numeric[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(numeric[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(numeric[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(numeric[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(numeric[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(numeric[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(numeric[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(numeric[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_vector"(numeric[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_vector"(numeric[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_vector"(numeric[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_vector"(numeric[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_to_float4"("public"."halfvec", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_to_float4"("public"."halfvec", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_to_float4"("public"."halfvec", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_to_float4"("public"."halfvec", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec"("public"."halfvec", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec"("public"."halfvec", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec"("public"."halfvec", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec"("public"."halfvec", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_to_sparsevec"("public"."halfvec", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_to_sparsevec"("public"."halfvec", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_to_sparsevec"("public"."halfvec", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_to_sparsevec"("public"."halfvec", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_to_vector"("public"."halfvec", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_to_vector"("public"."halfvec", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_to_vector"("public"."halfvec", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_to_vector"("public"."halfvec", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_to_halfvec"("public"."sparsevec", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_to_halfvec"("public"."sparsevec", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_to_halfvec"("public"."sparsevec", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_to_halfvec"("public"."sparsevec", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec"("public"."sparsevec", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec"("public"."sparsevec", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec"("public"."sparsevec", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec"("public"."sparsevec", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_to_vector"("public"."sparsevec", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_to_vector"("public"."sparsevec", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_to_vector"("public"."sparsevec", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_to_vector"("public"."sparsevec", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_to_float4"("public"."vector", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_to_float4"("public"."vector", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_to_float4"("public"."vector", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_to_float4"("public"."vector", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_to_halfvec"("public"."vector", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_to_halfvec"("public"."vector", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_to_halfvec"("public"."vector", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_to_halfvec"("public"."vector", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_to_sparsevec"("public"."vector", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_to_sparsevec"("public"."vector", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_to_sparsevec"("public"."vector", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_to_sparsevec"("public"."vector", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector"("public"."vector", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector"("public"."vector", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."vector"("public"."vector", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector"("public"."vector", integer, boolean) TO "service_role";

























































































































































GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_email_status_activity"() TO "anon";
GRANT ALL ON FUNCTION "public"."create_email_status_activity"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_email_status_activity"() TO "service_role";



GRANT ALL ON FUNCTION "public"."debug_pipeline_stages"("org_id" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."debug_pipeline_stages"("org_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."debug_pipeline_stages"("org_id" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."filter_companies_for_campaign"("p_organization_id" "text", "p_company_data" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."filter_companies_for_campaign"("p_organization_id" "text", "p_company_data" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."filter_companies_for_campaign"("p_organization_id" "text", "p_company_data" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_campaign_contacts"("p_campaign_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_campaign_contacts"("p_campaign_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_campaign_contacts"("p_campaign_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_campaign_summary"("p_campaign_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_campaign_summary"("p_campaign_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_campaign_summary"("p_campaign_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_companies_by_campaign"("p_organization_id" "text", "p_campaign_id" "uuid", "p_status" "text", "p_search" "text", "p_sort_by" "text", "p_sort_order" "text", "p_page" integer, "p_limit" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_companies_by_campaign"("p_organization_id" "text", "p_campaign_id" "uuid", "p_status" "text", "p_search" "text", "p_sort_by" "text", "p_sort_order" "text", "p_page" integer, "p_limit" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_companies_by_campaign"("p_organization_id" "text", "p_campaign_id" "uuid", "p_status" "text", "p_search" "text", "p_sort_by" "text", "p_sort_order" "text", "p_page" integer, "p_limit" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_contact_campaigns"("p_contact_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_contact_campaigns"("p_contact_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_contact_campaigns"("p_contact_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_dashboard_stats"("p_organization_id" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_dashboard_stats"("p_organization_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_dashboard_stats"("p_organization_id" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_organization_summary"("p_organization_id" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_organization_summary"("p_organization_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_organization_summary"("p_organization_id" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_sales_pipeline_analytics"("org_id" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_sales_pipeline_analytics"("org_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_sales_pipeline_analytics"("org_id" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_task_status_counts"("org_id" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_task_status_counts"("org_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_task_status_counts"("org_id" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_token_usage_by_date_range"("p_organization_id" "text", "p_start_date" timestamp with time zone, "p_end_date" timestamp with time zone, "p_provider" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_token_usage_by_date_range"("p_organization_id" "text", "p_start_date" timestamp with time zone, "p_end_date" timestamp with time zone, "p_provider" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_token_usage_by_date_range"("p_organization_id" "text", "p_start_date" timestamp with time zone, "p_end_date" timestamp with time zone, "p_provider" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_token_usage_stats"("p_organization_id" "text", "p_start_date" "date", "p_end_date" "date", "p_model_name" "text", "p_campaign_id" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_token_usage_stats"("p_organization_id" "text", "p_start_date" "date", "p_end_date" "date", "p_model_name" "text", "p_campaign_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_token_usage_stats"("p_organization_id" "text", "p_start_date" "date", "p_end_date" "date", "p_model_name" "text", "p_campaign_id" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_token_usage_summary"("p_organization_id" "text", "p_start_date" "date", "p_end_date" "date", "p_model_name" "text", "p_campaign_id" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_token_usage_summary"("p_organization_id" "text", "p_start_date" "date", "p_end_date" "date", "p_model_name" "text", "p_campaign_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_token_usage_summary"("p_organization_id" "text", "p_start_date" "date", "p_end_date" "date", "p_model_name" "text", "p_campaign_id" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_unified_token_usage_by_date_range"("p_organization_id" "text", "p_start_date" timestamp with time zone, "p_end_date" timestamp with time zone, "p_provider" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_unified_token_usage_by_date_range"("p_organization_id" "text", "p_start_date" timestamp with time zone, "p_end_date" timestamp with time zone, "p_provider" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_unified_token_usage_by_date_range"("p_organization_id" "text", "p_start_date" timestamp with time zone, "p_end_date" timestamp with time zone, "p_provider" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_unused_companies_for_outreach"("p_organization_id" "text", "p_limit" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_unused_companies_for_outreach"("p_organization_id" "text", "p_limit" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_unused_companies_for_outreach"("p_organization_id" "text", "p_limit" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_usage_by_date_range"("p_organization_id" "text", "p_start_date" "date", "p_end_date" "date", "p_provider" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_usage_by_date_range"("p_organization_id" "text", "p_start_date" "date", "p_end_date" "date", "p_provider" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_usage_by_date_range"("p_organization_id" "text", "p_start_date" "date", "p_end_date" "date", "p_provider" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."gin_extract_query_trgm"("text", "internal", smallint, "internal", "internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gin_extract_query_trgm"("text", "internal", smallint, "internal", "internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gin_extract_query_trgm"("text", "internal", smallint, "internal", "internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gin_extract_query_trgm"("text", "internal", smallint, "internal", "internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gin_extract_value_trgm"("text", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gin_extract_value_trgm"("text", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gin_extract_value_trgm"("text", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gin_extract_value_trgm"("text", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gin_trgm_consistent"("internal", smallint, "text", integer, "internal", "internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gin_trgm_consistent"("internal", smallint, "text", integer, "internal", "internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gin_trgm_consistent"("internal", smallint, "text", integer, "internal", "internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gin_trgm_consistent"("internal", smallint, "text", integer, "internal", "internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gin_trgm_triconsistent"("internal", smallint, "text", integer, "internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gin_trgm_triconsistent"("internal", smallint, "text", integer, "internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gin_trgm_triconsistent"("internal", smallint, "text", integer, "internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gin_trgm_triconsistent"("internal", smallint, "text", integer, "internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_consistent"("internal", "text", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_consistent"("internal", "text", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_consistent"("internal", "text", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_consistent"("internal", "text", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_decompress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_decompress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_decompress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_decompress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_distance"("internal", "text", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_distance"("internal", "text", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_distance"("internal", "text", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_distance"("internal", "text", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_options"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_options"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_options"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_options"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_same"("public"."gtrgm", "public"."gtrgm", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_same"("public"."gtrgm", "public"."gtrgm", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_same"("public"."gtrgm", "public"."gtrgm", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_same"("public"."gtrgm", "public"."gtrgm", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_accum"(double precision[], "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_accum"(double precision[], "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_accum"(double precision[], "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_accum"(double precision[], "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_add"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_add"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_add"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_add"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_avg"(double precision[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_avg"(double precision[]) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_avg"(double precision[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_avg"(double precision[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_cmp"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_cmp"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_cmp"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_cmp"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_combine"(double precision[], double precision[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_combine"(double precision[], double precision[]) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_combine"(double precision[], double precision[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_combine"(double precision[], double precision[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_concat"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_concat"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_concat"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_concat"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_eq"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_eq"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_eq"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_eq"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_ge"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_ge"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_ge"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_ge"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_gt"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_gt"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_gt"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_gt"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_l2_squared_distance"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_l2_squared_distance"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_l2_squared_distance"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_l2_squared_distance"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_le"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_le"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_le"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_le"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_lt"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_lt"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_lt"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_lt"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_mul"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_mul"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_mul"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_mul"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_ne"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_ne"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_ne"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_ne"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_negative_inner_product"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_negative_inner_product"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_negative_inner_product"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_negative_inner_product"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_spherical_distance"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_spherical_distance"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_spherical_distance"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_spherical_distance"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_sub"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_sub"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_sub"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_sub"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."hamming_distance"(bit, bit) TO "postgres";
GRANT ALL ON FUNCTION "public"."hamming_distance"(bit, bit) TO "anon";
GRANT ALL ON FUNCTION "public"."hamming_distance"(bit, bit) TO "authenticated";
GRANT ALL ON FUNCTION "public"."hamming_distance"(bit, bit) TO "service_role";



GRANT ALL ON FUNCTION "public"."hnsw_bit_support"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."hnsw_bit_support"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."hnsw_bit_support"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hnsw_bit_support"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."hnsw_halfvec_support"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."hnsw_halfvec_support"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."hnsw_halfvec_support"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hnsw_halfvec_support"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."hnsw_sparsevec_support"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."hnsw_sparsevec_support"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."hnsw_sparsevec_support"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hnsw_sparsevec_support"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."hnswhandler"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."hnswhandler"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."hnswhandler"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hnswhandler"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."inner_product"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."inner_product"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."inner_product"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."ivfflat_bit_support"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."ivfflat_bit_support"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."ivfflat_bit_support"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ivfflat_bit_support"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."ivfflat_halfvec_support"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."ivfflat_halfvec_support"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."ivfflat_halfvec_support"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ivfflat_halfvec_support"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."ivfflathandler"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."ivfflathandler"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."ivfflathandler"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ivfflathandler"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."jaccard_distance"(bit, bit) TO "postgres";
GRANT ALL ON FUNCTION "public"."jaccard_distance"(bit, bit) TO "anon";
GRANT ALL ON FUNCTION "public"."jaccard_distance"(bit, bit) TO "authenticated";
GRANT ALL ON FUNCTION "public"."jaccard_distance"(bit, bit) TO "service_role";



GRANT ALL ON FUNCTION "public"."l1_distance"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."l1_distance"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."l1_distance"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."l2_distance"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."l2_distance"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."l2_distance"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."l2_norm"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_norm"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_norm"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_norm"("public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."l2_norm"("public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_norm"("public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_norm"("public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_norm"("public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."log_file_upload"() TO "anon";
GRANT ALL ON FUNCTION "public"."log_file_upload"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."log_file_upload"() TO "service_role";



GRANT ALL ON FUNCTION "public"."mark_companies_for_outreach"("p_organization_id" "text", "p_campaign_id" "uuid", "p_campaign_name" "text", "p_company_identifiers" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."mark_companies_for_outreach"("p_organization_id" "text", "p_campaign_id" "uuid", "p_campaign_name" "text", "p_company_identifiers" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mark_companies_for_outreach"("p_organization_id" "text", "p_campaign_id" "uuid", "p_campaign_name" "text", "p_company_identifiers" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."remove_deleted_file_from_companies"() TO "anon";
GRANT ALL ON FUNCTION "public"."remove_deleted_file_from_companies"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."remove_deleted_file_from_companies"() TO "service_role";



GRANT ALL ON FUNCTION "public"."reset_icp_blocking_for_profile"("profile_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."reset_icp_blocking_for_profile"("profile_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."reset_icp_blocking_for_profile"("profile_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_limit"(real) TO "postgres";
GRANT ALL ON FUNCTION "public"."set_limit"(real) TO "anon";
GRANT ALL ON FUNCTION "public"."set_limit"(real) TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_limit"(real) TO "service_role";



GRANT ALL ON FUNCTION "public"."set_task_priority_rank"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_task_priority_rank"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_task_priority_rank"() TO "service_role";



GRANT ALL ON FUNCTION "public"."show_limit"() TO "postgres";
GRANT ALL ON FUNCTION "public"."show_limit"() TO "anon";
GRANT ALL ON FUNCTION "public"."show_limit"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."show_limit"() TO "service_role";



GRANT ALL ON FUNCTION "public"."show_trgm"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."show_trgm"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."show_trgm"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."show_trgm"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."similarity"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."similarity"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."similarity"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."similarity"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."similarity_dist"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."similarity_dist"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."similarity_dist"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."similarity_dist"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."similarity_op"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."similarity_op"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."similarity_op"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."similarity_op"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_cmp"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_cmp"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_cmp"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_cmp"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_eq"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_eq"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_eq"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_eq"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_ge"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_ge"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_ge"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_ge"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_gt"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_gt"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_gt"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_gt"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_l2_squared_distance"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_l2_squared_distance"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_l2_squared_distance"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_l2_squared_distance"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_le"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_le"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_le"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_le"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_lt"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_lt"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_lt"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_lt"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_ne"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_ne"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_ne"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_ne"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_negative_inner_product"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_negative_inner_product"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_negative_inner_product"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_negative_inner_product"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."strict_word_similarity"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."strict_word_similarity"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."strict_word_similarity"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."strict_word_similarity"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."strict_word_similarity_commutator_op"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_commutator_op"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_commutator_op"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_commutator_op"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."strict_word_similarity_dist_commutator_op"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_dist_commutator_op"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_dist_commutator_op"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_dist_commutator_op"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."strict_word_similarity_dist_op"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_dist_op"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_dist_op"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_dist_op"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."strict_word_similarity_op"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_op"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_op"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_op"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."subvector"("public"."halfvec", integer, integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."subvector"("public"."halfvec", integer, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."subvector"("public"."halfvec", integer, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."subvector"("public"."halfvec", integer, integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."subvector"("public"."vector", integer, integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."subvector"("public"."vector", integer, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."subvector"("public"."vector", integer, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."subvector"("public"."vector", integer, integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."update_campaign_companies_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_campaign_companies_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_campaign_companies_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_campaign_total_companies"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_campaign_total_companies"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_campaign_total_companies"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_company_blocked_status"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_company_blocked_status"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_company_blocked_status"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_company_contacts_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_company_contacts_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_company_contacts_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_deep_research_settings_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_deep_research_settings_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_deep_research_settings_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_organization_settings_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_organization_settings_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_organization_settings_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_selected_company_ids"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_selected_company_ids"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_selected_company_ids"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_system_config_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_system_config_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_system_config_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_usage_summary"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_usage_summary"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_usage_summary"() TO "service_role";



GRANT ALL ON TABLE "public"."style_guidelines" TO "anon";
GRANT ALL ON TABLE "public"."style_guidelines" TO "authenticated";
GRANT ALL ON TABLE "public"."style_guidelines" TO "service_role";



GRANT ALL ON FUNCTION "public"."upsert_style_guidelines"("p_organization_id" "text", "p_brand_voice" "text", "p_tone_attributes" "text"[], "p_key_phrases" "text"[], "p_avoid_phrases" "text"[], "p_writing_style" "text", "p_target_audience" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."upsert_style_guidelines"("p_organization_id" "text", "p_brand_voice" "text", "p_tone_attributes" "text"[], "p_key_phrases" "text"[], "p_avoid_phrases" "text"[], "p_writing_style" "text", "p_target_audience" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."upsert_style_guidelines"("p_organization_id" "text", "p_brand_voice" "text", "p_tone_attributes" "text"[], "p_key_phrases" "text"[], "p_avoid_phrases" "text"[], "p_writing_style" "text", "p_target_audience" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_task_contact"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_task_contact"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_task_contact"() TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_accum"(double precision[], "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_accum"(double precision[], "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_accum"(double precision[], "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_accum"(double precision[], "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_add"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_add"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_add"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_add"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_avg"(double precision[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_avg"(double precision[]) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_avg"(double precision[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_avg"(double precision[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_cmp"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_cmp"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_cmp"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_cmp"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_combine"(double precision[], double precision[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_combine"(double precision[], double precision[]) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_combine"(double precision[], double precision[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_combine"(double precision[], double precision[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_concat"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_concat"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_concat"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_concat"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_dims"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_dims"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_dims"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_dims"("public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_dims"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_dims"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_dims"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_dims"("public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_eq"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_eq"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_eq"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_eq"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_ge"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_ge"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_ge"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_ge"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_gt"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_gt"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_gt"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_gt"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_l2_squared_distance"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_l2_squared_distance"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_l2_squared_distance"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_l2_squared_distance"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_le"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_le"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_le"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_le"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_lt"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_lt"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_lt"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_lt"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_mul"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_mul"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_mul"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_mul"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_ne"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_ne"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_ne"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_ne"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_negative_inner_product"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_negative_inner_product"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_negative_inner_product"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_negative_inner_product"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_norm"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_norm"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_norm"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_norm"("public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_spherical_distance"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_spherical_distance"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_spherical_distance"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_spherical_distance"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_sub"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_sub"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_sub"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_sub"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."word_similarity"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."word_similarity"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."word_similarity"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."word_similarity"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."word_similarity_commutator_op"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."word_similarity_commutator_op"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."word_similarity_commutator_op"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."word_similarity_commutator_op"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."word_similarity_dist_commutator_op"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."word_similarity_dist_commutator_op"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."word_similarity_dist_commutator_op"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."word_similarity_dist_commutator_op"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."word_similarity_dist_op"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."word_similarity_dist_op"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."word_similarity_dist_op"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."word_similarity_dist_op"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."word_similarity_op"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."word_similarity_op"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."word_similarity_op"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."word_similarity_op"("text", "text") TO "service_role";












GRANT ALL ON FUNCTION "public"."avg"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."avg"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."avg"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."avg"("public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."avg"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."avg"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."avg"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."avg"("public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."sum"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sum"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."sum"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sum"("public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sum"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."sum"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."sum"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sum"("public"."vector") TO "service_role";









GRANT ALL ON TABLE "public"."campaign_activities" TO "anon";
GRANT ALL ON TABLE "public"."campaign_activities" TO "authenticated";
GRANT ALL ON TABLE "public"."campaign_activities" TO "service_role";



GRANT ALL ON TABLE "public"."campaign_companies" TO "anon";
GRANT ALL ON TABLE "public"."campaign_companies" TO "authenticated";
GRANT ALL ON TABLE "public"."campaign_companies" TO "service_role";



GRANT ALL ON TABLE "public"."campaign_emails" TO "anon";
GRANT ALL ON TABLE "public"."campaign_emails" TO "authenticated";
GRANT ALL ON TABLE "public"."campaign_emails" TO "service_role";



GRANT ALL ON TABLE "public"."campaign_files" TO "anon";
GRANT ALL ON TABLE "public"."campaign_files" TO "authenticated";
GRANT ALL ON TABLE "public"."campaign_files" TO "service_role";



GRANT ALL ON TABLE "public"."campaign_seed_companies" TO "anon";
GRANT ALL ON TABLE "public"."campaign_seed_companies" TO "authenticated";
GRANT ALL ON TABLE "public"."campaign_seed_companies" TO "service_role";



GRANT ALL ON TABLE "public"."campaigns" TO "anon";
GRANT ALL ON TABLE "public"."campaigns" TO "authenticated";
GRANT ALL ON TABLE "public"."campaigns" TO "service_role";



GRANT ALL ON TABLE "public"."companies" TO "anon";
GRANT ALL ON TABLE "public"."companies" TO "authenticated";
GRANT ALL ON TABLE "public"."companies" TO "service_role";



GRANT ALL ON TABLE "public"."company_activities" TO "anon";
GRANT ALL ON TABLE "public"."company_activities" TO "authenticated";
GRANT ALL ON TABLE "public"."company_activities" TO "service_role";



GRANT ALL ON TABLE "public"."company_contacts" TO "anon";
GRANT ALL ON TABLE "public"."company_contacts" TO "authenticated";
GRANT ALL ON TABLE "public"."company_contacts" TO "service_role";



GRANT ALL ON TABLE "public"."contact_activities" TO "anon";
GRANT ALL ON TABLE "public"."contact_activities" TO "authenticated";
GRANT ALL ON TABLE "public"."contact_activities" TO "service_role";



GRANT ALL ON TABLE "public"."contact_channels" TO "anon";
GRANT ALL ON TABLE "public"."contact_channels" TO "authenticated";
GRANT ALL ON TABLE "public"."contact_channels" TO "service_role";



GRANT ALL ON TABLE "public"."contact_notes" TO "anon";
GRANT ALL ON TABLE "public"."contact_notes" TO "authenticated";
GRANT ALL ON TABLE "public"."contact_notes" TO "service_role";



GRANT ALL ON TABLE "public"."contacts" TO "anon";
GRANT ALL ON TABLE "public"."contacts" TO "authenticated";
GRANT ALL ON TABLE "public"."contacts" TO "service_role";



GRANT ALL ON TABLE "public"."conversation_messages" TO "anon";
GRANT ALL ON TABLE "public"."conversation_messages" TO "authenticated";
GRANT ALL ON TABLE "public"."conversation_messages" TO "service_role";



GRANT ALL ON TABLE "public"."conversations" TO "anon";
GRANT ALL ON TABLE "public"."conversations" TO "authenticated";
GRANT ALL ON TABLE "public"."conversations" TO "service_role";



GRANT ALL ON TABLE "public"."token_usage" TO "anon";
GRANT ALL ON TABLE "public"."token_usage" TO "authenticated";
GRANT ALL ON TABLE "public"."token_usage" TO "service_role";



GRANT ALL ON TABLE "public"."daily_token_usage" TO "anon";
GRANT ALL ON TABLE "public"."daily_token_usage" TO "authenticated";
GRANT ALL ON TABLE "public"."daily_token_usage" TO "service_role";



GRANT ALL ON TABLE "public"."usage" TO "anon";
GRANT ALL ON TABLE "public"."usage" TO "authenticated";
GRANT ALL ON TABLE "public"."usage" TO "service_role";



GRANT ALL ON TABLE "public"."daily_usage_stats" TO "anon";
GRANT ALL ON TABLE "public"."daily_usage_stats" TO "authenticated";
GRANT ALL ON TABLE "public"."daily_usage_stats" TO "service_role";



GRANT ALL ON TABLE "public"."document_access_events" TO "anon";
GRANT ALL ON TABLE "public"."document_access_events" TO "authenticated";
GRANT ALL ON TABLE "public"."document_access_events" TO "service_role";



GRANT ALL ON TABLE "public"."document_short_urls" TO "anon";
GRANT ALL ON TABLE "public"."document_short_urls" TO "authenticated";
GRANT ALL ON TABLE "public"."document_short_urls" TO "service_role";



GRANT ALL ON TABLE "public"."feedback" TO "anon";
GRANT ALL ON TABLE "public"."feedback" TO "authenticated";
GRANT ALL ON TABLE "public"."feedback" TO "service_role";



GRANT ALL ON SEQUENCE "public"."feedback_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."feedback_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."feedback_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."icp_profiles" TO "anon";
GRANT ALL ON TABLE "public"."icp_profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."icp_profiles" TO "service_role";



GRANT ALL ON TABLE "public"."interview" TO "anon";
GRANT ALL ON TABLE "public"."interview" TO "authenticated";
GRANT ALL ON TABLE "public"."interview" TO "service_role";



GRANT ALL ON TABLE "public"."interviewer" TO "anon";
GRANT ALL ON TABLE "public"."interviewer" TO "authenticated";
GRANT ALL ON TABLE "public"."interviewer" TO "service_role";



GRANT ALL ON SEQUENCE "public"."interviewer_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."interviewer_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."interviewer_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."organization" TO "anon";
GRANT ALL ON TABLE "public"."organization" TO "authenticated";
GRANT ALL ON TABLE "public"."organization" TO "service_role";



GRANT ALL ON TABLE "public"."organization_files" TO "anon";
GRANT ALL ON TABLE "public"."organization_files" TO "authenticated";
GRANT ALL ON TABLE "public"."organization_files" TO "service_role";



GRANT ALL ON TABLE "public"."organization_icp_linkedin_urls" TO "anon";
GRANT ALL ON TABLE "public"."organization_icp_linkedin_urls" TO "authenticated";
GRANT ALL ON TABLE "public"."organization_icp_linkedin_urls" TO "service_role";



GRANT ALL ON TABLE "public"."organization_settings" TO "anon";
GRANT ALL ON TABLE "public"."organization_settings" TO "authenticated";
GRANT ALL ON TABLE "public"."organization_settings" TO "service_role";



GRANT ALL ON TABLE "public"."response" TO "anon";
GRANT ALL ON TABLE "public"."response" TO "authenticated";
GRANT ALL ON TABLE "public"."response" TO "service_role";



GRANT ALL ON SEQUENCE "public"."response_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."response_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."response_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."style_guidelines_backup" TO "anon";
GRANT ALL ON TABLE "public"."style_guidelines_backup" TO "authenticated";
GRANT ALL ON TABLE "public"."style_guidelines_backup" TO "service_role";



GRANT ALL ON SEQUENCE "public"."style_guidelines_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."style_guidelines_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."style_guidelines_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."system_config" TO "anon";
GRANT ALL ON TABLE "public"."system_config" TO "authenticated";
GRANT ALL ON TABLE "public"."system_config" TO "service_role";



GRANT ALL ON TABLE "public"."tasks" TO "anon";
GRANT ALL ON TABLE "public"."tasks" TO "authenticated";
GRANT ALL ON TABLE "public"."tasks" TO "service_role";



GRANT ALL ON SEQUENCE "public"."token_usage_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."token_usage_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."token_usage_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."usage_cost_by_context" TO "anon";
GRANT ALL ON TABLE "public"."usage_cost_by_context" TO "authenticated";
GRANT ALL ON TABLE "public"."usage_cost_by_context" TO "service_role";



GRANT ALL ON TABLE "public"."usage_cost_daily" TO "anon";
GRANT ALL ON TABLE "public"."usage_cost_daily" TO "authenticated";
GRANT ALL ON TABLE "public"."usage_cost_daily" TO "service_role";



GRANT ALL ON TABLE "public"."usage_cost_daily_by_campaign" TO "anon";
GRANT ALL ON TABLE "public"."usage_cost_daily_by_campaign" TO "authenticated";
GRANT ALL ON TABLE "public"."usage_cost_daily_by_campaign" TO "service_role";



GRANT ALL ON TABLE "public"."usage_cost_daily_by_context" TO "anon";
GRANT ALL ON TABLE "public"."usage_cost_daily_by_context" TO "authenticated";
GRANT ALL ON TABLE "public"."usage_cost_daily_by_context" TO "service_role";



GRANT ALL ON TABLE "public"."usage_cost_daily_with_split" TO "anon";
GRANT ALL ON TABLE "public"."usage_cost_daily_with_split" TO "authenticated";
GRANT ALL ON TABLE "public"."usage_cost_daily_with_split" TO "service_role";



GRANT ALL ON TABLE "public"."usage_cost_monthly" TO "anon";
GRANT ALL ON TABLE "public"."usage_cost_monthly" TO "authenticated";
GRANT ALL ON TABLE "public"."usage_cost_monthly" TO "service_role";



GRANT ALL ON TABLE "public"."usage_cost_monthly_by_campaign" TO "anon";
GRANT ALL ON TABLE "public"."usage_cost_monthly_by_campaign" TO "authenticated";
GRANT ALL ON TABLE "public"."usage_cost_monthly_by_campaign" TO "service_role";



GRANT ALL ON TABLE "public"."usage_cost_monthly_by_context" TO "anon";
GRANT ALL ON TABLE "public"."usage_cost_monthly_by_context" TO "authenticated";
GRANT ALL ON TABLE "public"."usage_cost_monthly_by_context" TO "service_role";



GRANT ALL ON TABLE "public"."usage_cost_monthly_with_split" TO "anon";
GRANT ALL ON TABLE "public"."usage_cost_monthly_with_split" TO "authenticated";
GRANT ALL ON TABLE "public"."usage_cost_monthly_with_split" TO "service_role";



GRANT ALL ON SEQUENCE "public"."usage_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."usage_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."usage_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."usage_summary" TO "anon";
GRANT ALL ON TABLE "public"."usage_summary" TO "authenticated";
GRANT ALL ON TABLE "public"."usage_summary" TO "service_role";



GRANT ALL ON SEQUENCE "public"."usage_summary_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."usage_summary_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."usage_summary_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."user" TO "anon";
GRANT ALL ON TABLE "public"."user" TO "authenticated";
GRANT ALL ON TABLE "public"."user" TO "service_role";



GRANT ALL ON TABLE "public"."user_organizations" TO "anon";
GRANT ALL ON TABLE "public"."user_organizations" TO "authenticated";
GRANT ALL ON TABLE "public"."user_organizations" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "service_role";






























