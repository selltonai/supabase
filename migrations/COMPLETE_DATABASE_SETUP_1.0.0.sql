-- =============================================================================
-- COMPLETE DATABASE SETUP - ALL TABLES + INDEXES + CONSTRAINTS
-- =============================================================================
-- ✅ COPY-PASTE THIS ENTIRE FILE INTO SUPABASE SQL EDITOR
--
-- This creates EVERYTHING:
-- - All enum types
-- - All tables (30+ tables)
-- - All indexes (50+ performance indexes)
-- - All foreign keys
-- - All constraints
--
-- Time to run: 1-2 minutes
-- Can be run on an empty database or existing (will skip what exists)
-- =============================================================================

BEGIN;

-- =============================================================================
-- PART 1: EXTENSIONS
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- =============================================================================
-- PART 2: ENUM TYPES
-- =============================================================================

DO $$ BEGIN CREATE TYPE plan AS ENUM ('free', 'starter', 'professional', 'enterprise');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE email_status AS ENUM ('draft', 'pending', 'sent', 'delivered', 'opened', 'clicked', 'replied', 'bounced', 'failed');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE campaign_status AS ENUM ('draft', 'active', 'paused', 'completed', 'archived', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE activity_type AS ENUM ('email_sent', 'email_opened', 'email_clicked', 'email_replied', 'email_bounced', 'meeting_booked', 'note_added', 'status_changed', 'call_made', 'linkedin_message', 'document_shared');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE channel_type AS ENUM ('email', 'phone', 'linkedin', 'whatsapp', 'sms', 'other');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE task_status AS ENUM ('pending', 'in_review', 'approved', 'rejected', 'completed', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE task_type AS ENUM ('email_draft', 'follow_up', 'meeting', 'research', 'other');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE file_category_enum AS ENUM ('documents', 'images', 'presentations', 'spreadsheets', 'case_studies', 'proposals', 'other');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- =============================================================================
-- PART 3: CORE TABLES
-- =============================================================================

-- Organization (root entity)
CREATE TABLE IF NOT EXISTS organization (
  id text PRIMARY KEY,
  created_at timestamptz NOT NULL DEFAULT now(),
  name text,
  image_url text,
  allowed_responses_count integer NOT NULL DEFAULT 0 CHECK (allowed_responses_count >= 0),
  plan plan DEFAULT 'free'
);

-- User
CREATE TABLE IF NOT EXISTS "user" (
  id text PRIMARY KEY,
  created_at timestamptz NOT NULL DEFAULT now(),
  email text NOT NULL UNIQUE
);

-- User-Organization relationship
CREATE TABLE IF NOT EXISTS user_organizations (
  user_id text NOT NULL REFERENCES "user"(id) ON DELETE CASCADE,
  organization_id text NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, organization_id)
);

-- =============================================================================
-- PART 4: ORGANIZATION SETTINGS
-- =============================================================================

CREATE TABLE IF NOT EXISTS organization_settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL UNIQUE REFERENCES organization(id) ON DELETE CASCADE,
  general_settings jsonb NOT NULL DEFAULT '{}'::jsonb,
  notification_settings jsonb NOT NULL DEFAULT '{}'::jsonb,
  api_credentials jsonb NOT NULL DEFAULT '{"cal_com_api_key": "", "calendly_api_key": ""}'::jsonb,
  onboarding_completed boolean NOT NULL DEFAULT false,
  onboarding_completed_at timestamptz,
  onboarding_skipped boolean NOT NULL DEFAULT false,
  onboarding_skipped_at timestamptz,
  company_website text,
  company_linkedin_profile text,
  company_description text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS deep_research_settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL UNIQUE REFERENCES organization(id) ON DELETE CASCADE,
  selected_providers text[] NOT NULL DEFAULT '{}'::text[],
  selected_research_types text[] NOT NULL DEFAULT '{}'::text[],
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS organization_icp_linkedin_urls (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
  url text NOT NULL,
  url_type text NOT NULL CHECK (url_type IN ('current_customer', 'ideal_customer', 'ideal_person', 'exclusion')),
  added_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, url, url_type)
);

CREATE TABLE IF NOT EXISTS style_guidelines (
  id serial PRIMARY KEY,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  organization_id text NOT NULL UNIQUE REFERENCES organization(id) ON DELETE CASCADE,
  brand_voice text,
  tone_attributes text[],
  key_phrases text[],
  avoid_phrases text[],
  writing_style text,
  target_audience text,
  tone_of_voice_sound text,
  tone_of_voice_emotions text[],
  tone_of_voice_personality_traits text[],
  key_word_choices_lexical_fields jsonb DEFAULT '{}'::jsonb,
  key_word_choices_dictionary jsonb DEFAULT '[]'::jsonb,
  writing_style_formality text,
  writing_style_sentence_voice text
);

CREATE TABLE IF NOT EXISTS system_config (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  key text NOT NULL UNIQUE,
  value jsonb NOT NULL,
  description text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- =============================================================================
-- PART 5: FILES & DOCUMENTS
-- =============================================================================

CREATE TABLE IF NOT EXISTS organization_files (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
  file_name text NOT NULL,
  file_type text NOT NULL,
  file_url text NOT NULL,
  file_size integer NOT NULL CHECK (file_size >= 0),
  file_category file_category_enum NOT NULL DEFAULT 'documents',
  full_text text,
  pages_count integer NOT NULL DEFAULT 0 CHECK (pages_count >= 0),
  shared_with_client boolean NOT NULL DEFAULT false,
  uploaded_by text NOT NULL,
  uploaded_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS organization_files_chunks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
  file_id uuid NOT NULL REFERENCES organization_files(id) ON DELETE CASCADE,
  chunk_text text NOT NULL,
  embedding vector,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- =============================================================================
-- PART 6: COMPANIES
-- =============================================================================

CREATE TABLE IF NOT EXISTS companies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
  name text NOT NULL,
  website text,
  linkedin_url text,
  universal_name text,
  company_type text,
  description text,
  tagline text,
  logo text,
  cover text,
  size text,
  employee_count integer CHECK (employee_count IS NULL OR employee_count >= 0),
  founded_year integer CHECK (founded_year IS NULL OR (founded_year >= 1800 AND founded_year <= EXTRACT(YEAR FROM CURRENT_DATE))),
  followers integer CHECK (followers IS NULL OR followers >= 0),
  location text,
  locations jsonb NOT NULL DEFAULT '{}'::jsonb,
  industries text[],
  specialities text[] NOT NULL DEFAULT '{}'::text[],
  hashtags text[] NOT NULL DEFAULT '{}'::text[],
  object_urn bigint,
  entity_urn text,
  used_for_outreach boolean NOT NULL DEFAULT false,
  phone text,
  icp_score jsonb,
  outreach_strategy jsonb,
  deep_research jsonb,
  useful_case_file_ids uuid[] NOT NULL DEFAULT '{}'::uuid[],
  funding_data jsonb NOT NULL DEFAULT '{}'::jsonb,
  b2b_result jsonb,
  processing_status text NOT NULL DEFAULT 'pending' CHECK (processing_status IN ('pending', 'processing', 'completed', 'failed')),
  processing_simple_status text GENERATED ALWAYS AS (
    CASE
      WHEN processing_status = 'completed' THEN 'processed'
      WHEN processing_status IN ('pending', 'processing') THEN 'processing'
      WHEN processing_status = 'failed' THEN 'failed'
      ELSE NULL
    END
  ) STORED,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- =============================================================================
-- PART 7: CONTACTS
-- =============================================================================

CREATE TABLE IF NOT EXISTS contacts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
  name text NOT NULL,
  firstname text,
  lastname text,
  email text,
  linkedin_url text,
  url text,
  identifier text,
  entity_urn text,
  object_urn bigint,
  universal_name text,
  headline text,
  summary text,
  industry text,
  picture text,
  background text,
  birth_date text,
  location jsonb,
  open_to_work boolean NOT NULL DEFAULT false,
  influencer boolean NOT NULL DEFAULT false,
  premium boolean NOT NULL DEFAULT false,
  educations jsonb,
  certifications jsonb,
  languages jsonb,
  skills jsonb,
  organizations jsonb NOT NULL DEFAULT '{}'::jsonb,
  patents jsonb NOT NULL DEFAULT '{}'::jsonb,
  awards jsonb NOT NULL DEFAULT '{}'::jsonb,
  projects jsonb NOT NULL DEFAULT '{}'::jsonb,
  publications jsonb NOT NULL DEFAULT '{}'::jsonb,
  courses jsonb NOT NULL DEFAULT '{}'::jsonb,
  test_scores jsonb NOT NULL DEFAULT '{}'::jsonb,
  position_groups jsonb NOT NULL DEFAULT '{}'::jsonb,
  volunteer_experiences jsonb NOT NULL DEFAULT '{}'::jsonb,
  recommendations text[] NOT NULL DEFAULT '{}'::text[],
  network_info jsonb NOT NULL DEFAULT '{}'::jsonb,
  analysis jsonb,
  activities jsonb,
  email_validation_response jsonb,
  processing_status text NOT NULL DEFAULT 'pending' CHECK (processing_status IN ('pending', 'processing', 'completed', 'failed')),
  processing_simple_status text GENERATED ALWAYS AS (
    CASE
      WHEN processing_status = 'completed' THEN 'processed'
      WHEN processing_status IN ('pending', 'processing') THEN 'processing'
      WHEN processing_status = 'failed' THEN 'failed'
      ELSE NULL
    END
  ) STORED,
  pipeline_stage text CHECK (pipeline_stage IS NULL OR pipeline_stage IN ('PROSPECT', 'LEAD', 'APPOINTMENT_REQUESTED', 'APPOINTMENT_SCHEDULED', 'APPOINTMENT_CANCELLED', 'PRESENTATION_SCHEDULED', 'CONTRACT_NEGOTIATIONS', 'AGREEMENT_IN_PRINCIPLE', 'CLOSED_WON', 'CLOSED_LOST', 'REENGAGEMENT')),
  stage_updated_at timestamptz,
  last_email_sentiment text CHECK (last_email_sentiment IS NULL OR last_email_sentiment IN ('VERY_POSITIVE', 'POSITIVE', 'NEUTRAL', 'NEGATIVE', 'VERY_NEGATIVE')),
  last_email_intent jsonb,
  last_thread_id text,
  last_incoming_email_at timestamptz,
  ooo_until timestamptz,
  unsubscribed_at timestamptz,
  stop_drafts boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Note: processing_simple_status for contacts is a regular text column that should be computed by application logic
-- or updated via triggers, as PostgreSQL doesn't support generating columns based on other columns in different contexts

CREATE TABLE IF NOT EXISTS company_contacts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  contact_id uuid NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
  organization_id text NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, contact_id)
);

CREATE TABLE IF NOT EXISTS contact_channels (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  contact_id uuid NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
  organization_id text NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
  channel_type channel_type NOT NULL,
  channel_value text NOT NULL,
  is_primary boolean NOT NULL DEFAULT false,
  is_verified boolean NOT NULL DEFAULT false,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (contact_id, channel_type, channel_value)
);

CREATE TABLE IF NOT EXISTS contact_notes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  contact_id uuid NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
  organization_id text NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
  user_id text REFERENCES "user"(id) ON DELETE SET NULL,
  content text NOT NULL,
  note_type text NOT NULL DEFAULT 'general',
  is_pinned boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- =============================================================================
-- PART 8: CAMPAIGNS
-- =============================================================================

CREATE TABLE IF NOT EXISTS campaigns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
  user_id text NOT NULL,
  name text NOT NULL,
  description text,
  campaign_type text NOT NULL DEFAULT 'email',
  status campaign_status NOT NULL DEFAULT 'draft',
  tags text[] NOT NULL DEFAULT '{}'::text[],
  icp_min_employees integer CHECK (icp_min_employees IS NULL OR icp_min_employees >= 0),
  icp_max_employees integer CHECK (icp_max_employees IS NULL OR icp_max_employees >= 0),
  icp_sales_process text[] NOT NULL DEFAULT '{}'::text[],
  icp_industries text[] NOT NULL DEFAULT '{}'::text[],
  icp_job_titles text[] NOT NULL DEFAULT '{}'::text[],
  icp_primary_regions text[] NOT NULL DEFAULT '{}'::text[],
  icp_secondary_regions text[] NOT NULL DEFAULT '{}'::text[],
  icp_focus_areas text[] NOT NULL DEFAULT '{}'::text[],
  icp_pain_points text[] NOT NULL DEFAULT '{}'::text[],
  icp_keywords text[] NOT NULL DEFAULT '{}'::text[],
  target_audience jsonb NOT NULL DEFAULT '{}'::jsonb,
  settings jsonb NOT NULL DEFAULT '{}'::jsonb,
  product_description text,
  lead_source text,
  b2b_results jsonb,
  csv_results jsonb,
  curated_companies jsonb,
  selected_company_ids text[] NOT NULL DEFAULT '{}'::text[],
  total_companies integer NOT NULL DEFAULT 0 CHECK (total_companies >= 0),
  estimated_total_companies integer,
  b2b_search_filters jsonb NOT NULL DEFAULT '{}'::jsonb,
  b2b_search_page_size integer,
  b2b_search_last_page integer,
  b2b_search_total_pages integer,
  b2b_search_total_elements integer,
  csv_processed_index text[] NOT NULL DEFAULT '{}'::text[],
  processing_status text NOT NULL DEFAULT 'pending',
  processing_started_at timestamptz,
  processing_completed_at timestamptz,
  total_contacts integer NOT NULL DEFAULT 0 CHECK (total_contacts >= 0),
  contacts_reached integer NOT NULL DEFAULT 0 CHECK (contacts_reached >= 0),
  contacts_replied integer NOT NULL DEFAULT 0 CHECK (contacts_replied >= 0),
  emails_sent integer NOT NULL DEFAULT 0 CHECK (emails_sent >= 0),
  emails_delivered integer NOT NULL DEFAULT 0 CHECK (emails_delivered >= 0),
  emails_opened integer NOT NULL DEFAULT 0 CHECK (emails_opened >= 0),
  emails_clicked integer NOT NULL DEFAULT 0 CHECK (emails_clicked >= 0),
  emails_replied integer NOT NULL DEFAULT 0 CHECK (emails_replied >= 0),
  emails_bounced integer NOT NULL DEFAULT 0 CHECK (emails_bounced >= 0),
  meetings_booked integer NOT NULL DEFAULT 0 CHECK (meetings_booked >= 0),
  current_step integer NOT NULL DEFAULT 0,
  completed_steps text[] NOT NULL DEFAULT '{}'::text[],
  wizard_completed boolean NOT NULL DEFAULT false,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  started_at timestamptz,
  launched_at timestamptz,
  completed_at timestamptz,
  CHECK (icp_min_employees IS NULL OR icp_max_employees IS NULL OR icp_min_employees <= icp_max_employees)
);

CREATE TABLE IF NOT EXISTS campaign_companies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id uuid NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  organization_id text NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (campaign_id, company_id)
);

CREATE TABLE IF NOT EXISTS campaign_emails (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id uuid NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
  contact_id uuid NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
  organization_id text NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
  subject text,
  content text,
  status email_status NOT NULL DEFAULT 'draft',
  message_id text,
  thread_id text,
  sent_at timestamptz,
  delivered_at timestamptz,
  opened_at timestamptz,
  first_opened_at timestamptz,
  clicked_at timestamptz,
  replied_at timestamptz,
  bounced_at timestamptz,
  reply_content text,
  reply_received_at timestamptz,
  open_count integer NOT NULL DEFAULT 0 CHECK (open_count >= 0),
  click_count integer NOT NULL DEFAULT 0 CHECK (click_count >= 0),
  error_message text,
  error_code text,
  approved_at timestamptz,
  approved_by_user_id text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS campaign_activities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id uuid NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
  contact_id uuid REFERENCES contacts(id) ON DELETE CASCADE,
  organization_id text NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
  user_id text,
  activity_type text NOT NULL,
  activity_data jsonb NOT NULL DEFAULT '{}'::jsonb,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now()
);

-- =============================================================================
-- PART 9: CONVERSATIONS & MESSAGES
-- =============================================================================

CREATE TABLE IF NOT EXISTS conversations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  contact_id uuid NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
  organization_id text NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
  user_id text REFERENCES "user"(id) ON DELETE SET NULL,
  subject text NOT NULL,
  channel_type channel_type NOT NULL DEFAULT 'email',
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'pending', 'closed')),
  priority text NOT NULL DEFAULT 'normal' CHECK (priority IN ('high', 'normal', 'low')),
  account_email text,
  is_unread boolean NOT NULL DEFAULT true,
  tags text[] NOT NULL DEFAULT '{}'::text[],
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  last_message_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS conversation_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  organization_id text NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
  sender_type text NOT NULL CHECK (sender_type IN ('user', 'contact')),
  sender_user_id text REFERENCES "user"(id) ON DELETE SET NULL,
  content text NOT NULL,
  subject text,
  channel_type channel_type NOT NULL DEFAULT 'email',
  message_type text NOT NULL DEFAULT 'text',
  email_message_id text,
  in_reply_to text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  sent_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- =============================================================================
-- PART 10: TASKS
-- =============================================================================

CREATE TABLE IF NOT EXISTS tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
  created_by_user_id text NOT NULL,
  completed_by_user_id text,
  title text NOT NULL,
  description text,
  task_type task_type,
  status task_status NOT NULL DEFAULT 'pending',
  priority text CHECK (priority IS NULL OR priority IN ('low', 'normal', 'high', 'urgent')),
  contact_id uuid REFERENCES contacts(id) ON DELETE CASCADE,
  company_id uuid REFERENCES companies(id) ON DELETE CASCADE,
  campaign_id uuid REFERENCES campaigns(id) ON DELETE CASCADE,
  thread_id text,
  email_id text,
  pre_generated_copy text,
  final_copy text,
  reasoning_note text,
  due_date timestamptz,
  scheduled_date timestamptz,
  completed_at timestamptz,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Email copy tasks (alternative to general tasks)
CREATE TABLE IF NOT EXISTS email_copy_tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL,
  contact_id uuid NOT NULL,
  company_id uuid NOT NULL,
  campaign_id uuid NOT NULL,
  thread_id text,
  subject text,
  reasoning_note text,
  body text,
  priority text NOT NULL DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'in_review', 'approved', 'rejected', 'sent')),
  send_status text NOT NULL DEFAULT 'not_sent' CHECK (send_status IN ('not_sent', 'sending', 'sent_success', 'sent_failed')),
  send_error_message text,
  sent_at timestamptz,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- =============================================================================
-- PART 11: ACTIVITIES
-- =============================================================================

CREATE TABLE IF NOT EXISTS contact_activities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  contact_id uuid NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
  organization_id text NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
  user_id text REFERENCES "user"(id) ON DELETE SET NULL,
  activity_type activity_type NOT NULL,
  title text NOT NULL,
  description text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  related_to_id uuid,
  related_to_type text,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS company_activities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  contact_id uuid REFERENCES contacts(id) ON DELETE SET NULL,
  campaign_id uuid REFERENCES campaigns(id) ON DELETE SET NULL,
  task_id uuid REFERENCES tasks(id) ON DELETE SET NULL,
  activity_type activity_type NOT NULL,
  title text NOT NULL,
  description text,
  created_by_user_id text NOT NULL,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- =============================================================================
-- PART 12: INTERVIEW SYSTEM
-- =============================================================================

CREATE TABLE IF NOT EXISTS interviewer (
  id serial PRIMARY KEY,
  created_at timestamptz NOT NULL DEFAULT now(),
  organization_id text NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
  agent_id text,
  name text NOT NULL,
  description text NOT NULL,
  image text NOT NULL,
  audio text,
  empathy integer NOT NULL CHECK (empathy >= 0 AND empathy <= 100),
  exploration integer NOT NULL CHECK (exploration >= 0 AND exploration <= 100),
  rapport integer NOT NULL CHECK (rapport >= 0 AND rapport <= 100),
  speed integer NOT NULL CHECK (speed >= 0 AND speed <= 100)
);

CREATE TABLE IF NOT EXISTS interview (
  id text PRIMARY KEY,
  created_at timestamptz NOT NULL DEFAULT now(),
  organization_id text NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
  user_id text REFERENCES "user"(id) ON DELETE SET NULL,
  interviewer_id integer REFERENCES interviewer(id) ON DELETE SET NULL,
  name text,
  description text,
  objective text,
  logo_url text,
  theme_color text,
  url text,
  readable_slug text,
  is_active boolean NOT NULL DEFAULT true,
  is_anonymous boolean NOT NULL DEFAULT false,
  is_archived boolean NOT NULL DEFAULT false,
  questions jsonb,
  quotes text[],
  insights text[],
  respondents text[],
  question_count integer,
  response_count integer,
  time_duration text
);

CREATE TABLE IF NOT EXISTS response (
  id serial PRIMARY KEY,
  created_at timestamptz NOT NULL DEFAULT now(),
  organization_id text NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
  interview_id text REFERENCES interview(id) ON DELETE CASCADE,
  name text,
  email text,
  call_id text,
  candidate_status text,
  duration integer CHECK (duration IS NULL OR duration >= 0),
  tab_switch_count integer NOT NULL DEFAULT 0 CHECK (tab_switch_count >= 0),
  details jsonb,
  analytics jsonb,
  is_analysed boolean NOT NULL DEFAULT false,
  is_ended boolean NOT NULL DEFAULT false,
  is_viewed boolean NOT NULL DEFAULT false
);

CREATE TABLE IF NOT EXISTS feedback (
  id serial PRIMARY KEY,
  created_at timestamptz NOT NULL DEFAULT now(),
  organization_id text NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
  interview_id text REFERENCES interview(id) ON DELETE CASCADE,
  email text,
  feedback text,
  satisfaction integer CHECK (satisfaction IS NULL OR (satisfaction >= 1 AND satisfaction <= 5))
);

-- =============================================================================
-- PART 13: USAGE TRACKING
-- =============================================================================

CREATE TABLE IF NOT EXISTS token_usage (
  id bigserial PRIMARY KEY,
  organization_id text NOT NULL,
  session_id text NOT NULL,
  provider text NOT NULL,
  model_name text,
  total_calls integer NOT NULL DEFAULT 0 CHECK (total_calls >= 0),
  total_input_tokens integer NOT NULL DEFAULT 0 CHECK (total_input_tokens >= 0),
  total_output_tokens integer NOT NULL DEFAULT 0 CHECK (total_output_tokens >= 0),
  total_tokens integer NOT NULL DEFAULT 0 CHECK (total_tokens >= 0),
  total_audio_tokens integer NOT NULL DEFAULT 0 CHECK (total_audio_tokens >= 0),
  total_cached_tokens integer NOT NULL DEFAULT 0 CHECK (total_cached_tokens >= 0),
  total_reasoning_tokens integer NOT NULL DEFAULT 0 CHECK (total_reasoning_tokens >= 0),
  total_prompt_tokens integer NOT NULL DEFAULT 0 CHECK (total_prompt_tokens >= 0),
  total_completion_tokens integer NOT NULL DEFAULT 0 CHECK (total_completion_tokens >= 0),
  total_processing_time numeric NOT NULL DEFAULT 0 CHECK (total_processing_time >= 0),
  tracking_start timestamptz NOT NULL,
  tracking_end timestamptz NOT NULL,
  run_id text,
  run_created_at timestamptz,
  agent_id text,
  content text,
  content_type text,
  event text,
  metrics_raw jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (tracking_start <= tracking_end)
);

CREATE TABLE IF NOT EXISTS usage (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL,
  session_id text NOT NULL,
  provider text NOT NULL,
  model_name text,
  api_calls integer NOT NULL DEFAULT 0 CHECK (api_calls >= 0),
  input_tokens integer NOT NULL DEFAULT 0 CHECK (input_tokens >= 0),
  output_tokens integer NOT NULL DEFAULT 0 CHECK (output_tokens >= 0),
  total_tokens integer NOT NULL DEFAULT 0 CHECK (total_tokens >= 0),
  run_id text,
  agent_id text,
  description text,
  usage_context text NOT NULL DEFAULT 'direct_api',
  tracking_start timestamptz NOT NULL DEFAULT now(),
  tracking_end timestamptz NOT NULL DEFAULT now(),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (tracking_start <= tracking_end)
);

CREATE TABLE IF NOT EXISTS usage_summary (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL,
  provider text NOT NULL,
  model_name text,
  date date NOT NULL,
  total_api_calls integer NOT NULL DEFAULT 0 CHECK (total_api_calls >= 0),
  total_input_tokens integer NOT NULL DEFAULT 0 CHECK (total_input_tokens >= 0),
  total_output_tokens integer NOT NULL DEFAULT 0 CHECK (total_output_tokens >= 0),
  total_tokens integer NOT NULL DEFAULT 0 CHECK (total_tokens >= 0),
  unique_sessions integer NOT NULL DEFAULT 0 CHECK (unique_sessions >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, provider, model_name, date)
);

-- =============================================================================
-- PART 14: PERFORMANCE INDEXES
-- =============================================================================

-- Organization indexes
CREATE INDEX IF NOT EXISTS idx_organization_settings_org_id ON organization_settings(organization_id);
CREATE INDEX IF NOT EXISTS idx_deep_research_settings_org_id ON deep_research_settings(organization_id);

-- Company indexes
CREATE INDEX IF NOT EXISTS idx_companies_org_id ON companies(organization_id);
CREATE INDEX IF NOT EXISTS idx_companies_processing_status ON companies(processing_status) WHERE processing_status IN ('pending', 'processing');
CREATE INDEX IF NOT EXISTS idx_companies_name_trgm ON companies USING gin(name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_companies_website ON companies(website) WHERE website IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_companies_linkedin_url ON companies(linkedin_url) WHERE linkedin_url IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_companies_used_for_outreach ON companies(organization_id, used_for_outreach) WHERE used_for_outreach = true;

-- Contact indexes
CREATE INDEX IF NOT EXISTS idx_contacts_org_id ON contacts(organization_id);
CREATE INDEX IF NOT EXISTS idx_contacts_email ON contacts(email) WHERE email IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_contacts_pipeline_stage ON contacts(organization_id, pipeline_stage) WHERE pipeline_stage IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_contacts_processing_status ON contacts(processing_status) WHERE processing_status IN ('pending', 'processing');
CREATE INDEX IF NOT EXISTS idx_contacts_name_trgm ON contacts USING gin(name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_contacts_unsubscribed ON contacts(organization_id) WHERE unsubscribed_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_contacts_stop_drafts ON contacts(organization_id) WHERE stop_drafts = true;

-- Relationship indexes
CREATE INDEX IF NOT EXISTS idx_company_contacts_company_id ON company_contacts(company_id);
CREATE INDEX IF NOT EXISTS idx_company_contacts_contact_id ON company_contacts(contact_id);
CREATE INDEX IF NOT EXISTS idx_company_contacts_org_id ON company_contacts(organization_id);
CREATE INDEX IF NOT EXISTS idx_contact_channels_contact_id ON contact_channels(contact_id);
CREATE INDEX IF NOT EXISTS idx_contact_channels_org_id ON contact_channels(organization_id);
CREATE INDEX IF NOT EXISTS idx_contact_channels_primary ON contact_channels(contact_id, is_primary) WHERE is_primary = true;

-- Campaign indexes
CREATE INDEX IF NOT EXISTS idx_campaigns_org_id ON campaigns(organization_id);
CREATE INDEX IF NOT EXISTS idx_campaigns_user_id ON campaigns(user_id);
CREATE INDEX IF NOT EXISTS idx_campaigns_status ON campaigns(organization_id, status);
CREATE INDEX IF NOT EXISTS idx_campaigns_processing_status ON campaigns(processing_status) WHERE processing_status IN ('pending', 'processing');
CREATE INDEX IF NOT EXISTS idx_campaigns_created_at ON campaigns(organization_id, created_at DESC);

-- Campaign relationships
CREATE INDEX IF NOT EXISTS idx_campaign_companies_campaign_id ON campaign_companies(campaign_id);
CREATE INDEX IF NOT EXISTS idx_campaign_companies_company_id ON campaign_companies(company_id);
CREATE INDEX IF NOT EXISTS idx_campaign_companies_org_id ON campaign_companies(organization_id);

-- Campaign email indexes (critical)
CREATE INDEX IF NOT EXISTS idx_campaign_emails_campaign_id ON campaign_emails(campaign_id);
CREATE INDEX IF NOT EXISTS idx_campaign_emails_contact_id ON campaign_emails(contact_id);
CREATE INDEX IF NOT EXISTS idx_campaign_emails_org_id ON campaign_emails(organization_id);
CREATE INDEX IF NOT EXISTS idx_campaign_emails_status ON campaign_emails(campaign_id, status);
CREATE INDEX IF NOT EXISTS idx_campaign_emails_thread_id ON campaign_emails(thread_id) WHERE thread_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_campaign_emails_message_id ON campaign_emails(message_id) WHERE message_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_campaign_emails_sent_at ON campaign_emails(campaign_id, sent_at) WHERE sent_at IS NOT NULL;

-- Campaign activity indexes
CREATE INDEX IF NOT EXISTS idx_campaign_activities_campaign_id ON campaign_activities(campaign_id);
CREATE INDEX IF NOT EXISTS idx_campaign_activities_contact_id ON campaign_activities(contact_id) WHERE contact_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_campaign_activities_org_id ON campaign_activities(organization_id);
CREATE INDEX IF NOT EXISTS idx_campaign_activities_occurred_at ON campaign_activities(campaign_id, occurred_at DESC);

-- Conversation indexes
CREATE INDEX IF NOT EXISTS idx_conversations_contact_id ON conversations(contact_id);
CREATE INDEX IF NOT EXISTS idx_conversations_org_id ON conversations(organization_id);
CREATE INDEX IF NOT EXISTS idx_conversations_user_id ON conversations(user_id) WHERE user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_conversations_status ON conversations(organization_id, status) WHERE status != 'closed';
CREATE INDEX IF NOT EXISTS idx_conversations_unread ON conversations(organization_id, is_unread) WHERE is_unread = true;
CREATE INDEX IF NOT EXISTS idx_conversations_last_message_at ON conversations(organization_id, last_message_at DESC);

-- Message indexes
CREATE INDEX IF NOT EXISTS idx_conversation_messages_conversation_id ON conversation_messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_conversation_messages_org_id ON conversation_messages(organization_id);
CREATE INDEX IF NOT EXISTS idx_conversation_messages_email_message_id ON conversation_messages(email_message_id) WHERE email_message_id IS NOT NULL;

-- Task indexes
CREATE INDEX IF NOT EXISTS idx_tasks_org_id ON tasks(organization_id);
CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(organization_id, status) WHERE status NOT IN ('completed', 'cancelled');
CREATE INDEX IF NOT EXISTS idx_tasks_contact_id ON tasks(contact_id) WHERE contact_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_tasks_company_id ON tasks(company_id) WHERE company_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_tasks_campaign_id ON tasks(campaign_id) WHERE campaign_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_tasks_due_date ON tasks(organization_id, due_date) WHERE due_date IS NOT NULL AND status NOT IN ('completed', 'cancelled');
CREATE INDEX IF NOT EXISTS idx_tasks_created_by ON tasks(created_by_user_id);

-- Activity indexes
CREATE INDEX IF NOT EXISTS idx_contact_activities_contact_id ON contact_activities(contact_id);
CREATE INDEX IF NOT EXISTS idx_contact_activities_org_id ON contact_activities(organization_id);
CREATE INDEX IF NOT EXISTS idx_contact_activities_occurred_at ON contact_activities(contact_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_company_activities_company_id ON company_activities(company_id);
CREATE INDEX IF NOT EXISTS idx_company_activities_org_id ON company_activities(organization_id);
CREATE INDEX IF NOT EXISTS idx_company_activities_created_at ON company_activities(company_id, created_at DESC);

-- File indexes
CREATE INDEX IF NOT EXISTS idx_organization_files_org_id ON organization_files(organization_id);
CREATE INDEX IF NOT EXISTS idx_organization_files_category ON organization_files(organization_id, file_category);
CREATE INDEX IF NOT EXISTS idx_organization_files_uploaded_at ON organization_files(organization_id, uploaded_at DESC);
CREATE INDEX IF NOT EXISTS idx_organization_files_chunks_file_id ON organization_files_chunks(file_id);
CREATE INDEX IF NOT EXISTS idx_organization_files_chunks_org_id ON organization_files_chunks(organization_id);

-- Usage indexes
CREATE INDEX IF NOT EXISTS idx_token_usage_org_session ON token_usage(organization_id, session_id);
CREATE INDEX IF NOT EXISTS idx_token_usage_tracking_start ON token_usage(tracking_start DESC);
CREATE INDEX IF NOT EXISTS idx_usage_org_session ON usage(organization_id, session_id);
CREATE INDEX IF NOT EXISTS idx_usage_summary_org_date ON usage_summary(organization_id, date DESC);

-- Interview indexes
CREATE INDEX IF NOT EXISTS idx_interview_org_id ON interview(organization_id);
CREATE INDEX IF NOT EXISTS idx_interview_user_id ON interview(user_id) WHERE user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_response_interview_id ON response(interview_id);
CREATE INDEX IF NOT EXISTS idx_response_org_id ON response(organization_id);
CREATE INDEX IF NOT EXISTS idx_feedback_interview_id ON feedback(interview_id);

-- =============================================================================
-- PART 15: DATABASE FUNCTIONS
-- =============================================================================

-- Dashboard stats function
DROP FUNCTION IF EXISTS get_dashboard_stats(text);

CREATE OR REPLACE FUNCTION get_dashboard_stats(p_org_id text)
RETURNS jsonb AS $$
DECLARE
  result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'tasks', (
      SELECT jsonb_build_object(
        'totalTasks', COUNT(*),
        'pendingTasks', COUNT(*) FILTER (WHERE status = 'pending'),
        'inProgressTasks', COUNT(*) FILTER (WHERE status = 'in_review'),
        'completedTasks', COUNT(*) FILTER (WHERE status = 'completed'),
        'cancelledTasks', COUNT(*) FILTER (WHERE status = 'cancelled'),
        'scheduledTasks', 0,
        'reviewDraftTasks', COUNT(*) FILTER (WHERE task_type = 'email_draft'),
        'meetingTasks', COUNT(*) FILTER (WHERE task_type = 'meeting'),
        'companyVerificationTasks', 0,
        'overdueTasks', COUNT(*) FILTER (WHERE status IN ('pending', 'in_review') AND due_date < NOW()),
        'dueTodayTasks', COUNT(*) FILTER (WHERE status IN ('pending', 'in_review') AND due_date >= DATE_TRUNC('day', NOW()) AND due_date < DATE_TRUNC('day', NOW()) + INTERVAL '1 day'),
        'dueThisWeekTasks', COUNT(*) FILTER (WHERE status IN ('pending', 'in_review') AND due_date >= DATE_TRUNC('week', NOW()) AND due_date < DATE_TRUNC('week', NOW()) + INTERVAL '1 week')
      )
      FROM tasks
      WHERE organization_id = p_org_id
    ),
    'contacts', (
      SELECT jsonb_build_object(
        'all_leads', COUNT(*) FILTER (WHERE organizations::jsonb->0->>'id' IS NOT NULL),
        'all_customers', COUNT(*) FILTER (WHERE pipeline_stage = 'CLOSED_WON'),
        'hot_leads', COUNT(*) FILTER (WHERE pipeline_stage IN ('APPOINTMENT_REQUESTED', 'PRESENTATION_SCHEDULED')),
        'new', COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '7 days'),
        'prospects', COUNT(*) FILTER (WHERE linkedin_url IS NOT NULL),
        'total_contacts', COUNT(*),
        'active_this_week', COUNT(*) FILTER (WHERE updated_at >= NOW() - INTERVAL '7 days'),
        'high_fit_score', COUNT(*) FILTER (WHERE pipeline_stage IN ('APPOINTMENT_REQUESTED', 'PRESENTATION_SCHEDULED', 'CLOSED_WON'))
      )
      FROM contacts
      WHERE organization_id = p_org_id
    ),
    'companies', (
      SELECT jsonb_build_object(
        'all_companies', COUNT(*),
        'cancelled', 0,
        'processed', COUNT(*) FILTER (WHERE processing_simple_status = 'processed'),
        'completed', COUNT(*) FILTER (WHERE used_for_outreach = true)
      )
      FROM companies
      WHERE organization_id = p_org_id
    )
  ) INTO result;
  
  RETURN result;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION get_dashboard_stats(text) IS 'Provides unified dashboard statistics including tasks, contacts, and companies counts';

-- Sales pipeline analytics function
DROP FUNCTION IF EXISTS get_sales_pipeline_analytics(TEXT);

CREATE OR REPLACE FUNCTION get_sales_pipeline_analytics(org_id TEXT)
RETURNS JSON AS $$
DECLARE
  pipeline_data JSON;
  industry_data JSON;
  location_data JSON;
  total_contacts INTEGER;
BEGIN
  -- Get total contacts
  SELECT COUNT(*) INTO total_contacts
  FROM contacts
  WHERE organization_id = org_id;

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
        ct.location->>'name' as location_name,
        COUNT(*) as count
      FROM contacts ct
      WHERE ct.organization_id = org_id
        AND ct.location IS NOT NULL
      GROUP BY location_name
      ORDER BY count DESC
      LIMIT 10
    )
    SELECT json_agg(
      json_build_object(
        'location', ls.location_name,
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
      'prospectToLead', (
        SELECT COALESCE(ROUND(
          COUNT(CASE WHEN UPPER(pipeline_stage) = 'LEAD' THEN 1 END)::numeric / 
          NULLIF(COUNT(CASE WHEN UPPER(pipeline_stage) = 'PROSPECT' THEN 1 END), 0) * 100, 2
        ), 0)
        FROM contacts
        WHERE organization_id = org_id
      ),
      'leadToAppointment', (
        SELECT COALESCE(ROUND(
          COUNT(CASE WHEN UPPER(pipeline_stage) IN ('APPOINTMENT_REQUESTED', 'APPOINTMENT_SCHEDULED') THEN 1 END)::numeric / 
          NULLIF(COUNT(CASE WHEN UPPER(pipeline_stage) = 'LEAD' THEN 1 END), 0) * 100, 2
        ), 0)
        FROM contacts
        WHERE organization_id = org_id
      ),
      'appointmentToPresentation', (
        SELECT COALESCE(ROUND(
          COUNT(CASE WHEN UPPER(pipeline_stage) = 'PRESENTATION_SCHEDULED' THEN 1 END)::numeric / 
          NULLIF(COUNT(CASE WHEN UPPER(pipeline_stage) IN ('APPOINTMENT_SCHEDULED') THEN 1 END), 0) * 100, 2
        ), 0)
        FROM contacts
        WHERE organization_id = org_id
      )
    )
  );
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION get_sales_pipeline_analytics(TEXT) IS 'Provides sales pipeline analytics including stages, industries, and conversion rates';

COMMIT;

-- =============================================================================
-- SUCCESS!
-- =============================================================================

DO $$ 
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '════════════════════════════════════════════════════════════════';
  RAISE NOTICE '✅ COMPLETE DATABASE SETUP FINISHED!';
  RAISE NOTICE '════════════════════════════════════════════════════════════════';
END $$;

