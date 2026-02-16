--
-- PostgreSQL database dump
--

\restrict FD5NQNtEOa4zNib21c8d2G5VrXzTRsMrHgOkV059dzT4vwcwfCeCed8DbOsgoeT

-- Dumped from database version 17.6
-- Dumped by pg_dump version 18.1 (Debian 18.1-2)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: auth; Type: SCHEMA; Schema: -; Owner: supabase_admin
--

CREATE SCHEMA auth;


ALTER SCHEMA auth OWNER TO supabase_admin;

--
-- Name: extensions; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA extensions;


ALTER SCHEMA extensions OWNER TO postgres;

--
-- Name: graphql; Type: SCHEMA; Schema: -; Owner: supabase_admin
--

CREATE SCHEMA graphql;


ALTER SCHEMA graphql OWNER TO supabase_admin;

--
-- Name: graphql_public; Type: SCHEMA; Schema: -; Owner: supabase_admin
--

CREATE SCHEMA graphql_public;


ALTER SCHEMA graphql_public OWNER TO supabase_admin;

--
-- Name: pgbouncer; Type: SCHEMA; Schema: -; Owner: pgbouncer
--

CREATE SCHEMA pgbouncer;


ALTER SCHEMA pgbouncer OWNER TO pgbouncer;

--
-- Name: realtime; Type: SCHEMA; Schema: -; Owner: supabase_admin
--

CREATE SCHEMA realtime;


ALTER SCHEMA realtime OWNER TO supabase_admin;

--
-- Name: storage; Type: SCHEMA; Schema: -; Owner: supabase_admin
--

CREATE SCHEMA storage;


ALTER SCHEMA storage OWNER TO supabase_admin;

--
-- Name: vault; Type: SCHEMA; Schema: -; Owner: supabase_admin
--

CREATE SCHEMA vault;


ALTER SCHEMA vault OWNER TO supabase_admin;

--
-- Name: pg_graphql; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_graphql WITH SCHEMA graphql;


--
-- Name: EXTENSION pg_graphql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pg_graphql IS 'pg_graphql: GraphQL support';


--
-- Name: pg_stat_statements; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA extensions;


--
-- Name: EXTENSION pg_stat_statements; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pg_stat_statements IS 'track planning and execution statistics of all SQL statements executed';


--
-- Name: pg_trgm; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;


--
-- Name: EXTENSION pg_trgm; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pg_trgm IS 'text similarity measurement and index searching based on trigrams';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: supabase_vault; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS supabase_vault WITH SCHEMA vault;


--
-- Name: EXTENSION supabase_vault; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION supabase_vault IS 'Supabase Vault Extension';


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: vector; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA public;


--
-- Name: EXTENSION vector; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION vector IS 'vector data type and ivfflat and hnsw access methods';


--
-- Name: aal_level; Type: TYPE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TYPE auth.aal_level AS ENUM (
    'aal1',
    'aal2',
    'aal3'
);


ALTER TYPE auth.aal_level OWNER TO supabase_auth_admin;

--
-- Name: code_challenge_method; Type: TYPE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TYPE auth.code_challenge_method AS ENUM (
    's256',
    'plain'
);


ALTER TYPE auth.code_challenge_method OWNER TO supabase_auth_admin;

--
-- Name: factor_status; Type: TYPE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TYPE auth.factor_status AS ENUM (
    'unverified',
    'verified'
);


ALTER TYPE auth.factor_status OWNER TO supabase_auth_admin;

--
-- Name: factor_type; Type: TYPE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TYPE auth.factor_type AS ENUM (
    'totp',
    'webauthn',
    'phone'
);


ALTER TYPE auth.factor_type OWNER TO supabase_auth_admin;

--
-- Name: oauth_authorization_status; Type: TYPE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TYPE auth.oauth_authorization_status AS ENUM (
    'pending',
    'approved',
    'denied',
    'expired'
);


ALTER TYPE auth.oauth_authorization_status OWNER TO supabase_auth_admin;

--
-- Name: oauth_client_type; Type: TYPE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TYPE auth.oauth_client_type AS ENUM (
    'public',
    'confidential'
);


ALTER TYPE auth.oauth_client_type OWNER TO supabase_auth_admin;

--
-- Name: oauth_registration_type; Type: TYPE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TYPE auth.oauth_registration_type AS ENUM (
    'dynamic',
    'manual'
);


ALTER TYPE auth.oauth_registration_type OWNER TO supabase_auth_admin;

--
-- Name: oauth_response_type; Type: TYPE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TYPE auth.oauth_response_type AS ENUM (
    'code'
);


ALTER TYPE auth.oauth_response_type OWNER TO supabase_auth_admin;

--
-- Name: one_time_token_type; Type: TYPE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TYPE auth.one_time_token_type AS ENUM (
    'confirmation_token',
    'reauthentication_token',
    'recovery_token',
    'email_change_token_new',
    'email_change_token_current',
    'phone_change_token'
);


ALTER TYPE auth.one_time_token_type OWNER TO supabase_auth_admin;

--
-- Name: activity_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.activity_type AS ENUM (
    'email_sent',
    'email_opened',
    'email_clicked',
    'email_replied',
    'email_bounced',
    'meeting_booked',
    'note_added',
    'status_changed',
    'call_made',
    'linkedin_message',
    'document_shared'
);


ALTER TYPE public.activity_type OWNER TO postgres;

--
-- Name: agent_event_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.agent_event_type AS ENUM (
    'RunResponse',
    'MessageResponse',
    'ToolResponse'
);


ALTER TYPE public.agent_event_type OWNER TO postgres;

--
-- Name: campaign_status; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.campaign_status AS ENUM (
    'draft',
    'active',
    'paused',
    'completed',
    'archived',
    'cancelled'
);


ALTER TYPE public.campaign_status OWNER TO postgres;

--
-- Name: channel_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.channel_type AS ENUM (
    'email',
    'phone',
    'linkedin',
    'whatsapp',
    'sms',
    'other'
);


ALTER TYPE public.channel_type OWNER TO postgres;

--
-- Name: company_activity_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.company_activity_type AS ENUM (
    'company_verification_approved',
    'company_verification_declined',
    'note_added',
    'meeting_prepared',
    'contact_added',
    'campaign_added',
    'icp_score_updated',
    'company_updated'
);


ALTER TYPE public.company_activity_type OWNER TO postgres;

--
-- Name: TYPE company_activity_type; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TYPE public.company_activity_type IS 'Valid activity types for company_activities table: company_verification_approved, company_verification_declined, note_added, meeting_prepared, contact_added, campaign_added, icp_score_updated, company_updated';


--
-- Name: email_status; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.email_status AS ENUM (
    'draft',
    'pending',
    'sent',
    'delivered',
    'opened',
    'clicked',
    'replied',
    'bounced',
    'failed'
);


ALTER TYPE public.email_status OWNER TO postgres;

--
-- Name: file_category_enum; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.file_category_enum AS ENUM (
    'documents',
    'images',
    'presentations',
    'spreadsheets',
    'case_studies',
    'proposals',
    'other',
    'transcripts',
    'internal_documents',
    'case_study',
    'sales_scripts',
    'sales_papers',
    'sait_guidelines',
    'brand_guidelines'
);


ALTER TYPE public.file_category_enum OWNER TO postgres;

--
-- Name: plan; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.plan AS ENUM (
    'free',
    'starter',
    'professional',
    'enterprise'
);


ALTER TYPE public.plan OWNER TO postgres;

--
-- Name: task_status; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.task_status AS ENUM (
    'pending',
    'in_progress',
    'completed',
    'failed',
    'cancelled',
    'scheduled'
);


ALTER TYPE public.task_status OWNER TO postgres;

--
-- Name: task_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.task_type AS ENUM (
    'email_draft',
    'follow_up',
    'meeting',
    'research',
    'other',
    'email_generation_processing',
    'company_verification',
    'review_draft'
);


ALTER TYPE public.task_type OWNER TO postgres;

--
-- Name: TYPE task_type; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TYPE public.task_type IS 'Valid task types: review_draft (email drafts to review), meeting (meeting scheduling), company_verification (company verification workflows), email_generation_processing (lock during email generation)';


--
-- Name: action; Type: TYPE; Schema: realtime; Owner: supabase_admin
--

CREATE TYPE realtime.action AS ENUM (
    'INSERT',
    'UPDATE',
    'DELETE',
    'TRUNCATE',
    'ERROR'
);


ALTER TYPE realtime.action OWNER TO supabase_admin;

--
-- Name: equality_op; Type: TYPE; Schema: realtime; Owner: supabase_admin
--

CREATE TYPE realtime.equality_op AS ENUM (
    'eq',
    'neq',
    'lt',
    'lte',
    'gt',
    'gte',
    'in'
);


ALTER TYPE realtime.equality_op OWNER TO supabase_admin;

--
-- Name: user_defined_filter; Type: TYPE; Schema: realtime; Owner: supabase_admin
--

CREATE TYPE realtime.user_defined_filter AS (
	column_name text,
	op realtime.equality_op,
	value text
);


ALTER TYPE realtime.user_defined_filter OWNER TO supabase_admin;

--
-- Name: wal_column; Type: TYPE; Schema: realtime; Owner: supabase_admin
--

CREATE TYPE realtime.wal_column AS (
	name text,
	type_name text,
	type_oid oid,
	value jsonb,
	is_pkey boolean,
	is_selectable boolean
);


ALTER TYPE realtime.wal_column OWNER TO supabase_admin;

--
-- Name: wal_rls; Type: TYPE; Schema: realtime; Owner: supabase_admin
--

CREATE TYPE realtime.wal_rls AS (
	wal jsonb,
	is_rls_enabled boolean,
	subscription_ids uuid[],
	errors text[]
);


ALTER TYPE realtime.wal_rls OWNER TO supabase_admin;

--
-- Name: buckettype; Type: TYPE; Schema: storage; Owner: supabase_storage_admin
--

CREATE TYPE storage.buckettype AS ENUM (
    'STANDARD',
    'ANALYTICS',
    'VECTOR'
);


ALTER TYPE storage.buckettype OWNER TO supabase_storage_admin;

--
-- Name: email(); Type: FUNCTION; Schema: auth; Owner: supabase_auth_admin
--

CREATE FUNCTION auth.email() RETURNS text
    LANGUAGE sql STABLE
    AS $$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.email', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email')
  )::text
$$;


ALTER FUNCTION auth.email() OWNER TO supabase_auth_admin;

--
-- Name: FUNCTION email(); Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON FUNCTION auth.email() IS 'Deprecated. Use auth.jwt() -> ''email'' instead.';


--
-- Name: jwt(); Type: FUNCTION; Schema: auth; Owner: supabase_auth_admin
--

CREATE FUNCTION auth.jwt() RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
  select 
    coalesce(
        nullif(current_setting('request.jwt.claim', true), ''),
        nullif(current_setting('request.jwt.claims', true), '')
    )::jsonb
$$;


ALTER FUNCTION auth.jwt() OWNER TO supabase_auth_admin;

--
-- Name: role(); Type: FUNCTION; Schema: auth; Owner: supabase_auth_admin
--

CREATE FUNCTION auth.role() RETURNS text
    LANGUAGE sql STABLE
    AS $$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  )::text
$$;


ALTER FUNCTION auth.role() OWNER TO supabase_auth_admin;

--
-- Name: FUNCTION role(); Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON FUNCTION auth.role() IS 'Deprecated. Use auth.jwt() -> ''role'' instead.';


--
-- Name: uid(); Type: FUNCTION; Schema: auth; Owner: supabase_auth_admin
--

CREATE FUNCTION auth.uid() RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;


ALTER FUNCTION auth.uid() OWNER TO supabase_auth_admin;

--
-- Name: FUNCTION uid(); Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON FUNCTION auth.uid() IS 'Deprecated. Use auth.jwt() -> ''sub'' instead.';


--
-- Name: grant_pg_cron_access(); Type: FUNCTION; Schema: extensions; Owner: supabase_admin
--

CREATE FUNCTION extensions.grant_pg_cron_access() RETURNS event_trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF EXISTS (
    SELECT
    FROM pg_event_trigger_ddl_commands() AS ev
    JOIN pg_extension AS ext
    ON ev.objid = ext.oid
    WHERE ext.extname = 'pg_cron'
  )
  THEN
    grant usage on schema cron to postgres with grant option;

    alter default privileges in schema cron grant all on tables to postgres with grant option;
    alter default privileges in schema cron grant all on functions to postgres with grant option;
    alter default privileges in schema cron grant all on sequences to postgres with grant option;

    alter default privileges for user supabase_admin in schema cron grant all
        on sequences to postgres with grant option;
    alter default privileges for user supabase_admin in schema cron grant all
        on tables to postgres with grant option;
    alter default privileges for user supabase_admin in schema cron grant all
        on functions to postgres with grant option;

    grant all privileges on all tables in schema cron to postgres with grant option;
    revoke all on table cron.job from postgres;
    grant select on table cron.job to postgres with grant option;
  END IF;
END;
$$;


ALTER FUNCTION extensions.grant_pg_cron_access() OWNER TO supabase_admin;

--
-- Name: FUNCTION grant_pg_cron_access(); Type: COMMENT; Schema: extensions; Owner: supabase_admin
--

COMMENT ON FUNCTION extensions.grant_pg_cron_access() IS 'Grants access to pg_cron';


--
-- Name: grant_pg_graphql_access(); Type: FUNCTION; Schema: extensions; Owner: supabase_admin
--

CREATE FUNCTION extensions.grant_pg_graphql_access() RETURNS event_trigger
    LANGUAGE plpgsql
    AS $_$
DECLARE
    func_is_graphql_resolve bool;
BEGIN
    func_is_graphql_resolve = (
        SELECT n.proname = 'resolve'
        FROM pg_event_trigger_ddl_commands() AS ev
        LEFT JOIN pg_catalog.pg_proc AS n
        ON ev.objid = n.oid
    );

    IF func_is_graphql_resolve
    THEN
        -- Update public wrapper to pass all arguments through to the pg_graphql resolve func
        DROP FUNCTION IF EXISTS graphql_public.graphql;
        create or replace function graphql_public.graphql(
            "operationName" text default null,
            query text default null,
            variables jsonb default null,
            extensions jsonb default null
        )
            returns jsonb
            language sql
        as $$
            select graphql.resolve(
                query := query,
                variables := coalesce(variables, '{}'),
                "operationName" := "operationName",
                extensions := extensions
            );
        $$;

        -- This hook executes when `graphql.resolve` is created. That is not necessarily the last
        -- function in the extension so we need to grant permissions on existing entities AND
        -- update default permissions to any others that are created after `graphql.resolve`
        grant usage on schema graphql to postgres, anon, authenticated, service_role;
        grant select on all tables in schema graphql to postgres, anon, authenticated, service_role;
        grant execute on all functions in schema graphql to postgres, anon, authenticated, service_role;
        grant all on all sequences in schema graphql to postgres, anon, authenticated, service_role;
        alter default privileges in schema graphql grant all on tables to postgres, anon, authenticated, service_role;
        alter default privileges in schema graphql grant all on functions to postgres, anon, authenticated, service_role;
        alter default privileges in schema graphql grant all on sequences to postgres, anon, authenticated, service_role;

        -- Allow postgres role to allow granting usage on graphql and graphql_public schemas to custom roles
        grant usage on schema graphql_public to postgres with grant option;
        grant usage on schema graphql to postgres with grant option;
    END IF;

END;
$_$;


ALTER FUNCTION extensions.grant_pg_graphql_access() OWNER TO supabase_admin;

--
-- Name: FUNCTION grant_pg_graphql_access(); Type: COMMENT; Schema: extensions; Owner: supabase_admin
--

COMMENT ON FUNCTION extensions.grant_pg_graphql_access() IS 'Grants access to pg_graphql';


--
-- Name: grant_pg_net_access(); Type: FUNCTION; Schema: extensions; Owner: supabase_admin
--

CREATE FUNCTION extensions.grant_pg_net_access() RETURNS event_trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_event_trigger_ddl_commands() AS ev
    JOIN pg_extension AS ext
    ON ev.objid = ext.oid
    WHERE ext.extname = 'pg_net'
  )
  THEN
    IF NOT EXISTS (
      SELECT 1
      FROM pg_roles
      WHERE rolname = 'supabase_functions_admin'
    )
    THEN
      CREATE USER supabase_functions_admin NOINHERIT CREATEROLE LOGIN NOREPLICATION;
    END IF;

    GRANT USAGE ON SCHEMA net TO supabase_functions_admin, postgres, anon, authenticated, service_role;

    IF EXISTS (
      SELECT FROM pg_extension
      WHERE extname = 'pg_net'
      -- all versions in use on existing projects as of 2025-02-20
      -- version 0.12.0 onwards don't need these applied
      AND extversion IN ('0.2', '0.6', '0.7', '0.7.1', '0.8', '0.10.0', '0.11.0')
    ) THEN
      ALTER function net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) SECURITY DEFINER;
      ALTER function net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) SECURITY DEFINER;

      ALTER function net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) SET search_path = net;
      ALTER function net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) SET search_path = net;

      REVOKE ALL ON FUNCTION net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) FROM PUBLIC;
      REVOKE ALL ON FUNCTION net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) FROM PUBLIC;

      GRANT EXECUTE ON FUNCTION net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) TO supabase_functions_admin, postgres, anon, authenticated, service_role;
      GRANT EXECUTE ON FUNCTION net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) TO supabase_functions_admin, postgres, anon, authenticated, service_role;
    END IF;
  END IF;
END;
$$;


ALTER FUNCTION extensions.grant_pg_net_access() OWNER TO supabase_admin;

--
-- Name: FUNCTION grant_pg_net_access(); Type: COMMENT; Schema: extensions; Owner: supabase_admin
--

COMMENT ON FUNCTION extensions.grant_pg_net_access() IS 'Grants access to pg_net';


--
-- Name: pgrst_ddl_watch(); Type: FUNCTION; Schema: extensions; Owner: supabase_admin
--

CREATE FUNCTION extensions.pgrst_ddl_watch() RETURNS event_trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN SELECT * FROM pg_event_trigger_ddl_commands()
  LOOP
    IF cmd.command_tag IN (
      'CREATE SCHEMA', 'ALTER SCHEMA'
    , 'CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO', 'ALTER TABLE'
    , 'CREATE FOREIGN TABLE', 'ALTER FOREIGN TABLE'
    , 'CREATE VIEW', 'ALTER VIEW'
    , 'CREATE MATERIALIZED VIEW', 'ALTER MATERIALIZED VIEW'
    , 'CREATE FUNCTION', 'ALTER FUNCTION'
    , 'CREATE TRIGGER'
    , 'CREATE TYPE', 'ALTER TYPE'
    , 'CREATE RULE'
    , 'COMMENT'
    )
    -- don't notify in case of CREATE TEMP table or other objects created on pg_temp
    AND cmd.schema_name is distinct from 'pg_temp'
    THEN
      NOTIFY pgrst, 'reload schema';
    END IF;
  END LOOP;
END; $$;


ALTER FUNCTION extensions.pgrst_ddl_watch() OWNER TO supabase_admin;

--
-- Name: pgrst_drop_watch(); Type: FUNCTION; Schema: extensions; Owner: supabase_admin
--

CREATE FUNCTION extensions.pgrst_drop_watch() RETURNS event_trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  obj record;
BEGIN
  FOR obj IN SELECT * FROM pg_event_trigger_dropped_objects()
  LOOP
    IF obj.object_type IN (
      'schema'
    , 'table'
    , 'foreign table'
    , 'view'
    , 'materialized view'
    , 'function'
    , 'trigger'
    , 'type'
    , 'rule'
    )
    AND obj.is_temporary IS false -- no pg_temp objects
    THEN
      NOTIFY pgrst, 'reload schema';
    END IF;
  END LOOP;
END; $$;


ALTER FUNCTION extensions.pgrst_drop_watch() OWNER TO supabase_admin;

--
-- Name: set_graphql_placeholder(); Type: FUNCTION; Schema: extensions; Owner: supabase_admin
--

CREATE FUNCTION extensions.set_graphql_placeholder() RETURNS event_trigger
    LANGUAGE plpgsql
    AS $_$
    DECLARE
    graphql_is_dropped bool;
    BEGIN
    graphql_is_dropped = (
        SELECT ev.schema_name = 'graphql_public'
        FROM pg_event_trigger_dropped_objects() AS ev
        WHERE ev.schema_name = 'graphql_public'
    );

    IF graphql_is_dropped
    THEN
        create or replace function graphql_public.graphql(
            "operationName" text default null,
            query text default null,
            variables jsonb default null,
            extensions jsonb default null
        )
            returns jsonb
            language plpgsql
        as $$
            DECLARE
                server_version float;
            BEGIN
                server_version = (SELECT (SPLIT_PART((select version()), ' ', 2))::float);

                IF server_version >= 14 THEN
                    RETURN jsonb_build_object(
                        'errors', jsonb_build_array(
                            jsonb_build_object(
                                'message', 'pg_graphql extension is not enabled.'
                            )
                        )
                    );
                ELSE
                    RETURN jsonb_build_object(
                        'errors', jsonb_build_array(
                            jsonb_build_object(
                                'message', 'pg_graphql is only available on projects running Postgres 14 onwards.'
                            )
                        )
                    );
                END IF;
            END;
        $$;
    END IF;

    END;
$_$;


ALTER FUNCTION extensions.set_graphql_placeholder() OWNER TO supabase_admin;

--
-- Name: FUNCTION set_graphql_placeholder(); Type: COMMENT; Schema: extensions; Owner: supabase_admin
--

COMMENT ON FUNCTION extensions.set_graphql_placeholder() IS 'Reintroduces placeholder function for graphql_public.graphql';


--
-- Name: get_auth(text); Type: FUNCTION; Schema: pgbouncer; Owner: supabase_admin
--

CREATE FUNCTION pgbouncer.get_auth(p_usename text) RETURNS TABLE(username text, password text)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
  BEGIN
      RAISE DEBUG 'PgBouncer auth request: %', p_usename;

      RETURN QUERY
      SELECT
          rolname::text,
          CASE WHEN rolvaliduntil < now()
              THEN null
              ELSE rolpassword::text
          END
      FROM pg_authid
      WHERE rolname=$1 and rolcanlogin;
  END;
  $_$;


ALTER FUNCTION pgbouncer.get_auth(p_usename text) OWNER TO supabase_admin;

--
-- Name: export_template_csv(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.export_template_csv(p_organization_id text) RETURNS TABLE("First Name" text, "Last Name" text, "Title" text, "Company Name" text, "Company website" text, "Personal LinkedIn" text, "Company LinkedIn" text, "Company email address" text, "Personal Email address" text, "Mobile Number" text, "Company Number" text, "Person location" text, "Company location" text, "Stage" text, "Technologies used" text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
    -- First Name
    COALESCE(c.firstname, SPLIT_PART(c.name, ' ', 1), '') AS "First Name",
    
    -- Last Name  
    COALESCE(c.lastname, 
        CASE 
            WHEN array_length(string_to_array(c.name, ' '), 1) > 1 
                THEN array_to_string((string_to_array(c.name, ' '))[2:], ' ')
            ELSE ''
        END, '') AS "Last Name",
    
    -- Title (Job Title)
    COALESCE(c.headline, '') AS "Title",
    
    -- Company Name
    COALESCE(comp.name, '') AS "Company Name",
    
    -- Company website
    COALESCE(comp.website, '') AS "Company website",
    
    -- Personal LinkedIn
    COALESCE(c.linkedin_url, '') AS "Personal LinkedIn",
    
    -- Company LinkedIn
    COALESCE(comp.linkedin_url, '') AS "Company LinkedIn",
    
    -- Company email address (leave empty - we don't store generic company emails)
    '' AS "Company email address",
    
    -- Personal Email address
    COALESCE(c.email, '') AS "Personal Email address",
    
    -- Mobile Number
    COALESCE(c.phone, '') AS "Mobile Number",
    
    -- Company Number
    COALESCE(comp.phone, '') AS "Company Number",
    
    -- Person location (single location name - prioritize city, then default, then country)
    COALESCE(
        CASE 
            WHEN c.location IS NOT NULL THEN
                CASE 
                    WHEN c.location->>'city' IS NOT NULL THEN c.location->>'city'
                    WHEN c.location->>'default' IS NOT NULL THEN c.location->>'default'
                    WHEN c.location->>'country' IS NOT NULL THEN c.location->>'country'
                    ELSE ''
                END
            ELSE ''
        END,
        ''
    ) AS "Person location",
    
    -- Company location
    COALESCE(comp.location, '') AS "Company location",
    
    -- Stage (Pipeline Stage) - default to PROSPECT if null
    COALESCE(c.pipeline_stage, 'PROSPECT') AS "Stage",
    
    -- Technologies used (from contacts skills or company specialities)
    COALESCE(
        CASE 
            WHEN c.skills IS NOT NULL AND jsonb_typeof(c.skills) = 'array' THEN
                ARRAY_TO_STRING(
                    ARRAY(SELECT jsonb_array_elements_text(c.skills)),
                    ', '
                )
            WHEN comp.specialities IS NOT NULL AND array_length(comp.specialities, 1) > 0 THEN
                ARRAY_TO_STRING(comp.specialities, ', ')
            ELSE ''
        END,
        ''
    ) AS "Technologies used"

    FROM contacts c
    -- Join with company_contacts to get company relationship
    LEFT JOIN company_contacts cc ON cc.contact_id = c.id AND cc.organization_id = c.organization_id
    -- Join with companies to get company data
    LEFT JOIN companies comp ON comp.id = cc.company_id AND comp.organization_id = c.organization_id

    WHERE 
        -- Filter by organization
        c.organization_id = p_organization_id
        
        -- Uncomment the line below to only show contacts WITH companies:
        -- AND comp.id IS NOT NULL
        
    ORDER BY comp.name NULLS LAST, c.name;
END;
$$;


ALTER FUNCTION public.export_template_csv(p_organization_id text) OWNER TO postgres;

--
-- Name: get_companies_by_campaign(text, uuid, text, text, text, text, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_companies_by_campaign(p_organization_id text, p_campaign_id uuid, p_status text DEFAULT NULL::text, p_search text DEFAULT NULL::text, p_sort_by text DEFAULT 'name'::text, p_sort_order text DEFAULT 'asc'::text, p_page integer DEFAULT 1, p_limit integer DEFAULT 50) RETURNS TABLE(id uuid, organization_id text, name text, website text, size text, linkedin_url text, description text, created_at timestamp with time zone, updated_at timestamp with time zone, used_for_outreach boolean, phone text, employee_count integer, logo text, location text, industries text[], icp_score jsonb, deep_research jsonb, outreach_strategy jsonb, universal_name text, company_type text, cover text, tagline text, founded_year integer, object_urn bigint, followers integer, locations jsonb, funding_data jsonb, specialities text[], hashtags text[], processing_status text, b2b_result jsonb, blocked_by_icp boolean, total_count bigint)
    LANGUAGE plpgsql SECURITY DEFINER
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


ALTER FUNCTION public.get_companies_by_campaign(p_organization_id text, p_campaign_id uuid, p_status text, p_search text, p_sort_by text, p_sort_order text, p_page integer, p_limit integer) OWNER TO postgres;

--
-- Name: get_dashboard_stats(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_dashboard_stats(p_organization_id text) RETURNS jsonb
    LANGUAGE plpgsql
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
        -- Task type counts - PENDING ONLY
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


ALTER FUNCTION public.get_dashboard_stats(p_organization_id text) OWNER TO postgres;

--
-- Name: get_organization_summary(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_organization_summary(p_organization_id text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
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


ALTER FUNCTION public.get_organization_summary(p_organization_id text) OWNER TO postgres;

--
-- Name: get_sales_pipeline_analytics(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_sales_pipeline_analytics(org_id text) RETURNS json
    LANGUAGE plpgsql STABLE
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


ALTER FUNCTION public.get_sales_pipeline_analytics(org_id text) OWNER TO postgres;

--
-- Name: FUNCTION get_sales_pipeline_analytics(org_id text); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.get_sales_pipeline_analytics(org_id text) IS 'Fixed conversion rate calculation - now uses cumulative stage progression.
Prospect→Lead: % of total contacts that reached Lead or beyond
Lead→Appointment: % of contacts at Lead+ that reached Appointment or beyond  
Appointment→Presentation: % of contacts with scheduled appointments that reached Presentation';


--
-- Name: get_token_usage_stats(text, date, date, text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_token_usage_stats(p_organization_id text, p_start_date date, p_end_date date, p_model_name text DEFAULT NULL::text, p_campaign_id text DEFAULT NULL::text) RETURNS TABLE(total_input_tokens bigint, total_output_tokens bigint, total_tokens bigint, total_processing_time numeric, total_runs bigint, total_api_calls bigint)
    LANGUAGE plpgsql STABLE
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


ALTER FUNCTION public.get_token_usage_stats(p_organization_id text, p_start_date date, p_end_date date, p_model_name text, p_campaign_id text) OWNER TO postgres;

--
-- Name: FUNCTION get_token_usage_stats(p_organization_id text, p_start_date date, p_end_date date, p_model_name text, p_campaign_id text); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.get_token_usage_stats(p_organization_id text, p_start_date date, p_end_date date, p_model_name text, p_campaign_id text) IS 'Returns aggregated token usage stats for an organization with proper UTC date handling';


--
-- Name: get_token_usage_summary(text, date, date, text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_token_usage_summary(p_organization_id text, p_start_date date, p_end_date date, p_model_name text DEFAULT NULL::text, p_campaign_id text DEFAULT NULL::text) RETURNS TABLE(period_start timestamp with time zone, total_input_tokens bigint, total_output_tokens bigint, total_tokens bigint, total_runs bigint, total_api_calls bigint, provider text, model_name text, unique_sessions bigint)
    LANGUAGE plpgsql STABLE
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


ALTER FUNCTION public.get_token_usage_summary(p_organization_id text, p_start_date date, p_end_date date, p_model_name text, p_campaign_id text) OWNER TO postgres;

--
-- Name: FUNCTION get_token_usage_summary(p_organization_id text, p_start_date date, p_end_date date, p_model_name text, p_campaign_id text); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.get_token_usage_summary(p_organization_id text, p_start_date date, p_end_date date, p_model_name text, p_campaign_id text) IS 'Returns daily token usage summary for an organization with proper UTC date handling';


--
-- Name: reset_icp_blocking_for_profile(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.reset_icp_blocking_for_profile(profile_id uuid) RETURNS integer
    LANGUAGE plpgsql
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


ALTER FUNCTION public.reset_icp_blocking_for_profile(profile_id uuid) OWNER TO postgres;

--
-- Name: FUNCTION reset_icp_blocking_for_profile(profile_id uuid); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.reset_icp_blocking_for_profile(profile_id uuid) IS 'Resets ICP blocking status for all companies that were blocked using a specific ICP profile. Use this when an ICP profile is updated to allow reprocessing.';


--
-- Name: search_similar_content(public.vector, text, double precision, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.search_similar_content(query_embedding public.vector, organization_id text, similarity_threshold double precision DEFAULT 0.7, max_results integer DEFAULT 10) RETURNS TABLE(id integer, url text, content text, similarity double precision)
    LANGUAGE plpgsql
    AS $_$
BEGIN
    -- Check if organization_id looks like a UUID
    IF organization_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
        RETURN QUERY SELECT * FROM search_similar_content_uuid(
            query_embedding,
            organization_id::uuid,
            similarity_threshold,
            max_results
        );
    ELSE
        RETURN QUERY SELECT * FROM search_similar_content_text(
            query_embedding,
            organization_id,
            similarity_threshold,
            max_results
        );
    END IF;
END;
$_$;


ALTER FUNCTION public.search_similar_content(query_embedding public.vector, organization_id text, similarity_threshold double precision, max_results integer) OWNER TO postgres;

--
-- Name: FUNCTION search_similar_content(query_embedding public.vector, organization_id text, similarity_threshold double precision, max_results integer); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.search_similar_content(query_embedding public.vector, organization_id text, similarity_threshold double precision, max_results integer) IS 'Search for similar content using cosine similarity. Works with both UUID and text organization IDs.';


--
-- Name: search_similar_content_text(public.vector, text, double precision, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.search_similar_content_text(query_embedding public.vector, organization_id text, similarity_threshold double precision DEFAULT 0.7, max_results integer DEFAULT 10) RETURNS TABLE(id integer, url text, content text, similarity double precision)
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Cosine Similarity = 1 - Cosine Distance
    RETURN QUERY
    SELECT
        d.id,
        d.url,
        d.content,
        1 - (d.embedding <=> query_embedding) AS similarity
    FROM
        datastore d
    WHERE
        d.organization_id = search_similar_content_text.organization_id
        AND 1 - (d.embedding <=> query_embedding) > similarity_threshold -- Filter based on cosine similarity
    ORDER BY
        d.embedding <=> query_embedding -- Order by cosine distance (ascending)
    LIMIT max_results;
END;
$$;


ALTER FUNCTION public.search_similar_content_text(query_embedding public.vector, organization_id text, similarity_threshold double precision, max_results integer) OWNER TO postgres;

--
-- Name: search_similar_content_uuid(public.vector, uuid, double precision, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.search_similar_content_uuid(query_embedding public.vector, organization_id uuid, similarity_threshold double precision DEFAULT 0.7, max_results integer DEFAULT 10) RETURNS TABLE(id integer, url text, content text, similarity double precision)
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Cosine Similarity = 1 - Cosine Distance
    RETURN QUERY
    SELECT
        d.id,
        d.url,
        d.content,
        1 - (d.embedding <=> query_embedding) AS similarity
    FROM
        datastore d
    WHERE
        -- Compare text representation for index usage, as datastore.organization_id is TEXT
        d.organization_id = organization_id::text
        AND 1 - (d.embedding <=> query_embedding) > similarity_threshold -- Filter based on cosine similarity
    ORDER BY
        d.embedding <=> query_embedding -- Order by cosine distance (ascending)
    LIMIT max_results;
END;
$$;


ALTER FUNCTION public.search_similar_content_uuid(query_embedding public.vector, organization_id uuid, similarity_threshold double precision, max_results integer) OWNER TO postgres;

--
-- Name: set_task_priority_rank(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.set_task_priority_rank() RETURNS trigger
    LANGUAGE plpgsql
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


ALTER FUNCTION public.set_task_priority_rank() OWNER TO postgres;

--
-- Name: update_company_blocked_status(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_company_blocked_status() RETURNS trigger
    LANGUAGE plpgsql
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


ALTER FUNCTION public.update_company_blocked_status() OWNER TO postgres;

--
-- Name: update_organization_settings_updated_at(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_organization_settings_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_organization_settings_updated_at() OWNER TO postgres;

--
-- Name: update_style_guidelines(text, jsonb, jsonb, jsonb, jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_style_guidelines(org_id text, tone jsonb, keywords jsonb, style jsonb, narratives jsonb) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Check if record exists
    IF EXISTS (SELECT 1 FROM style_guidelines WHERE organization_id = org_id) THEN
        -- Update existing record
        UPDATE style_guidelines
        SET 
            tone_of_voice = tone,
            key_word_choices = keywords,
            writing_style = style,
            narrative_techniques = narratives,
            created_at = NOW()
        WHERE organization_id = org_id;
    ELSE
        -- Insert new record
        INSERT INTO style_guidelines (
            organization_id,
            tone_of_voice,
            key_word_choices,
            writing_style,
            narrative_techniques
        ) VALUES (
            org_id,
            tone,
            keywords,
            style,
            narratives
        );
    END IF;
END;
$$;


ALTER FUNCTION public.update_style_guidelines(org_id text, tone jsonb, keywords jsonb, style jsonb, narratives jsonb) OWNER TO postgres;

--
-- Name: update_token_usage_summary(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_token_usage_summary() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO token_usage_summary (
        organization_id,
        model_name,
        period_start,
        period_end,
        total_runs,
        total_input_tokens,
        total_output_tokens,
        total_tokens,
        total_processing_time
    ) VALUES (
        NEW.organization_id,
        NEW.model_name,
        date_trunc('hour', NOW()),
        date_trunc('hour', NOW()) + interval '1 hour',
        1,
        NEW.total_input_tokens,
        NEW.total_output_tokens,
        NEW.total_tokens,
        NEW.total_processing_time
    )
    ON CONFLICT (organization_id, model_name, period_start, period_end)
    DO UPDATE SET
        total_runs = token_usage_summary.total_runs + 1,
        total_input_tokens = token_usage_summary.total_input_tokens + NEW.total_input_tokens,
        total_output_tokens = token_usage_summary.total_output_tokens + NEW.total_output_tokens,
        total_tokens = token_usage_summary.total_tokens + NEW.total_tokens,
        total_processing_time = token_usage_summary.total_processing_time + NEW.total_processing_time,
        updated_at = NOW();
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_token_usage_summary() OWNER TO postgres;

--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_updated_at_column() OWNER TO postgres;

--
-- Name: apply_rls(jsonb, integer); Type: FUNCTION; Schema: realtime; Owner: supabase_admin
--

CREATE FUNCTION realtime.apply_rls(wal jsonb, max_record_bytes integer DEFAULT (1024 * 1024)) RETURNS SETOF realtime.wal_rls
    LANGUAGE plpgsql
    AS $$
declare
-- Regclass of the table e.g. public.notes
entity_ regclass = (quote_ident(wal ->> 'schema') || '.' || quote_ident(wal ->> 'table'))::regclass;

-- I, U, D, T: insert, update ...
action realtime.action = (
    case wal ->> 'action'
        when 'I' then 'INSERT'
        when 'U' then 'UPDATE'
        when 'D' then 'DELETE'
        else 'ERROR'
    end
);

-- Is row level security enabled for the table
is_rls_enabled bool = relrowsecurity from pg_class where oid = entity_;

subscriptions realtime.subscription[] = array_agg(subs)
    from
        realtime.subscription subs
    where
        subs.entity = entity_
        -- Filter by action early - only get subscriptions interested in this action
        -- action_filter column can be: '*' (all), 'INSERT', 'UPDATE', or 'DELETE'
        and (subs.action_filter = '*' or subs.action_filter = action::text);

-- Subscription vars
roles regrole[] = array_agg(distinct us.claims_role::text)
    from
        unnest(subscriptions) us;

working_role regrole;
claimed_role regrole;
claims jsonb;

subscription_id uuid;
subscription_has_access bool;
visible_to_subscription_ids uuid[] = '{}';

-- structured info for wal's columns
columns realtime.wal_column[];
-- previous identity values for update/delete
old_columns realtime.wal_column[];

error_record_exceeds_max_size boolean = octet_length(wal::text) > max_record_bytes;

-- Primary jsonb output for record
output jsonb;

begin
perform set_config('role', null, true);

columns =
    array_agg(
        (
            x->>'name',
            x->>'type',
            x->>'typeoid',
            realtime.cast(
                (x->'value') #>> '{}',
                coalesce(
                    (x->>'typeoid')::regtype, -- null when wal2json version <= 2.4
                    (x->>'type')::regtype
                )
            ),
            (pks ->> 'name') is not null,
            true
        )::realtime.wal_column
    )
    from
        jsonb_array_elements(wal -> 'columns') x
        left join jsonb_array_elements(wal -> 'pk') pks
            on (x ->> 'name') = (pks ->> 'name');

old_columns =
    array_agg(
        (
            x->>'name',
            x->>'type',
            x->>'typeoid',
            realtime.cast(
                (x->'value') #>> '{}',
                coalesce(
                    (x->>'typeoid')::regtype, -- null when wal2json version <= 2.4
                    (x->>'type')::regtype
                )
            ),
            (pks ->> 'name') is not null,
            true
        )::realtime.wal_column
    )
    from
        jsonb_array_elements(wal -> 'identity') x
        left join jsonb_array_elements(wal -> 'pk') pks
            on (x ->> 'name') = (pks ->> 'name');

for working_role in select * from unnest(roles) loop

    -- Update `is_selectable` for columns and old_columns
    columns =
        array_agg(
            (
                c.name,
                c.type_name,
                c.type_oid,
                c.value,
                c.is_pkey,
                pg_catalog.has_column_privilege(working_role, entity_, c.name, 'SELECT')
            )::realtime.wal_column
        )
        from
            unnest(columns) c;

    old_columns =
            array_agg(
                (
                    c.name,
                    c.type_name,
                    c.type_oid,
                    c.value,
                    c.is_pkey,
                    pg_catalog.has_column_privilege(working_role, entity_, c.name, 'SELECT')
                )::realtime.wal_column
            )
            from
                unnest(old_columns) c;

    if action <> 'DELETE' and count(1) = 0 from unnest(columns) c where c.is_pkey then
        return next (
            jsonb_build_object(
                'schema', wal ->> 'schema',
                'table', wal ->> 'table',
                'type', action
            ),
            is_rls_enabled,
            -- subscriptions is already filtered by entity
            (select array_agg(s.subscription_id) from unnest(subscriptions) as s where claims_role = working_role),
            array['Error 400: Bad Request, no primary key']
        )::realtime.wal_rls;

    -- The claims role does not have SELECT permission to the primary key of entity
    elsif action <> 'DELETE' and sum(c.is_selectable::int) <> count(1) from unnest(columns) c where c.is_pkey then
        return next (
            jsonb_build_object(
                'schema', wal ->> 'schema',
                'table', wal ->> 'table',
                'type', action
            ),
            is_rls_enabled,
            (select array_agg(s.subscription_id) from unnest(subscriptions) as s where claims_role = working_role),
            array['Error 401: Unauthorized']
        )::realtime.wal_rls;

    else
        output = jsonb_build_object(
            'schema', wal ->> 'schema',
            'table', wal ->> 'table',
            'type', action,
            'commit_timestamp', to_char(
                ((wal ->> 'timestamp')::timestamptz at time zone 'utc'),
                'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
            ),
            'columns', (
                select
                    jsonb_agg(
                        jsonb_build_object(
                            'name', pa.attname,
                            'type', pt.typname
                        )
                        order by pa.attnum asc
                    )
                from
                    pg_attribute pa
                    join pg_type pt
                        on pa.atttypid = pt.oid
                where
                    attrelid = entity_
                    and attnum > 0
                    and pg_catalog.has_column_privilege(working_role, entity_, pa.attname, 'SELECT')
            )
        )
        -- Add "record" key for insert and update
        || case
            when action in ('INSERT', 'UPDATE') then
                jsonb_build_object(
                    'record',
                    (
                        select
                            jsonb_object_agg(
                                -- if unchanged toast, get column name and value from old record
                                coalesce((c).name, (oc).name),
                                case
                                    when (c).name is null then (oc).value
                                    else (c).value
                                end
                            )
                        from
                            unnest(columns) c
                            full outer join unnest(old_columns) oc
                                on (c).name = (oc).name
                        where
                            coalesce((c).is_selectable, (oc).is_selectable)
                            and ( not error_record_exceeds_max_size or (octet_length((c).value::text) <= 64))
                    )
                )
            else '{}'::jsonb
        end
        -- Add "old_record" key for update and delete
        || case
            when action = 'UPDATE' then
                jsonb_build_object(
                        'old_record',
                        (
                            select jsonb_object_agg((c).name, (c).value)
                            from unnest(old_columns) c
                            where
                                (c).is_selectable
                                and ( not error_record_exceeds_max_size or (octet_length((c).value::text) <= 64))
                        )
                    )
            when action = 'DELETE' then
                jsonb_build_object(
                    'old_record',
                    (
                        select jsonb_object_agg((c).name, (c).value)
                        from unnest(old_columns) c
                        where
                            (c).is_selectable
                            and ( not error_record_exceeds_max_size or (octet_length((c).value::text) <= 64))
                            and ( not is_rls_enabled or (c).is_pkey ) -- if RLS enabled, we can't secure deletes so filter to pkey
                    )
                )
            else '{}'::jsonb
        end;

        -- Create the prepared statement
        if is_rls_enabled and action <> 'DELETE' then
            if (select 1 from pg_prepared_statements where name = 'walrus_rls_stmt' limit 1) > 0 then
                deallocate walrus_rls_stmt;
            end if;
            execute realtime.build_prepared_statement_sql('walrus_rls_stmt', entity_, columns);
        end if;

        visible_to_subscription_ids = '{}';

        for subscription_id, claims in (
                select
                    subs.subscription_id,
                    subs.claims
                from
                    unnest(subscriptions) subs
                where
                    subs.entity = entity_
                    and subs.claims_role = working_role
                    and (
                        realtime.is_visible_through_filters(columns, subs.filters)
                        or (
                          action = 'DELETE'
                          and realtime.is_visible_through_filters(old_columns, subs.filters)
                        )
                    )
        ) loop

            if not is_rls_enabled or action = 'DELETE' then
                visible_to_subscription_ids = visible_to_subscription_ids || subscription_id;
            else
                -- Check if RLS allows the role to see the record
                perform
                    -- Trim leading and trailing quotes from working_role because set_config
                    -- doesn't recognize the role as valid if they are included
                    set_config('role', trim(both '"' from working_role::text), true),
                    set_config('request.jwt.claims', claims::text, true);

                execute 'execute walrus_rls_stmt' into subscription_has_access;

                if subscription_has_access then
                    visible_to_subscription_ids = visible_to_subscription_ids || subscription_id;
                end if;
            end if;
        end loop;

        perform set_config('role', null, true);

        return next (
            output,
            is_rls_enabled,
            visible_to_subscription_ids,
            case
                when error_record_exceeds_max_size then array['Error 413: Payload Too Large']
                else '{}'
            end
        )::realtime.wal_rls;

    end if;
end loop;

perform set_config('role', null, true);
end;
$$;


ALTER FUNCTION realtime.apply_rls(wal jsonb, max_record_bytes integer) OWNER TO supabase_admin;

--
-- Name: broadcast_changes(text, text, text, text, text, record, record, text); Type: FUNCTION; Schema: realtime; Owner: supabase_admin
--

CREATE FUNCTION realtime.broadcast_changes(topic_name text, event_name text, operation text, table_name text, table_schema text, new record, old record, level text DEFAULT 'ROW'::text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    -- Declare a variable to hold the JSONB representation of the row
    row_data jsonb := '{}'::jsonb;
BEGIN
    IF level = 'STATEMENT' THEN
        RAISE EXCEPTION 'function can only be triggered for each row, not for each statement';
    END IF;
    -- Check the operation type and handle accordingly
    IF operation = 'INSERT' OR operation = 'UPDATE' OR operation = 'DELETE' THEN
        row_data := jsonb_build_object('old_record', OLD, 'record', NEW, 'operation', operation, 'table', table_name, 'schema', table_schema);
        PERFORM realtime.send (row_data, event_name, topic_name);
    ELSE
        RAISE EXCEPTION 'Unexpected operation type: %', operation;
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Failed to process the row: %', SQLERRM;
END;

$$;


ALTER FUNCTION realtime.broadcast_changes(topic_name text, event_name text, operation text, table_name text, table_schema text, new record, old record, level text) OWNER TO supabase_admin;

--
-- Name: build_prepared_statement_sql(text, regclass, realtime.wal_column[]); Type: FUNCTION; Schema: realtime; Owner: supabase_admin
--

CREATE FUNCTION realtime.build_prepared_statement_sql(prepared_statement_name text, entity regclass, columns realtime.wal_column[]) RETURNS text
    LANGUAGE sql
    AS $$
      /*
      Builds a sql string that, if executed, creates a prepared statement to
      tests retrive a row from *entity* by its primary key columns.
      Example
          select realtime.build_prepared_statement_sql('public.notes', '{"id"}'::text[], '{"bigint"}'::text[])
      */
          select
      'prepare ' || prepared_statement_name || ' as
          select
              exists(
                  select
                      1
                  from
                      ' || entity || '
                  where
                      ' || string_agg(quote_ident(pkc.name) || '=' || quote_nullable(pkc.value #>> '{}') , ' and ') || '
              )'
          from
              unnest(columns) pkc
          where
              pkc.is_pkey
          group by
              entity
      $$;


ALTER FUNCTION realtime.build_prepared_statement_sql(prepared_statement_name text, entity regclass, columns realtime.wal_column[]) OWNER TO supabase_admin;

--
-- Name: cast(text, regtype); Type: FUNCTION; Schema: realtime; Owner: supabase_admin
--

CREATE FUNCTION realtime."cast"(val text, type_ regtype) RETURNS jsonb
    LANGUAGE plpgsql IMMUTABLE
    AS $$
    declare
      res jsonb;
    begin
      execute format('select to_jsonb(%L::'|| type_::text || ')', val)  into res;
      return res;
    end
    $$;


ALTER FUNCTION realtime."cast"(val text, type_ regtype) OWNER TO supabase_admin;

--
-- Name: check_equality_op(realtime.equality_op, regtype, text, text); Type: FUNCTION; Schema: realtime; Owner: supabase_admin
--

CREATE FUNCTION realtime.check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    AS $$
      /*
      Casts *val_1* and *val_2* as type *type_* and check the *op* condition for truthiness
      */
      declare
          op_symbol text = (
              case
                  when op = 'eq' then '='
                  when op = 'neq' then '!='
                  when op = 'lt' then '<'
                  when op = 'lte' then '<='
                  when op = 'gt' then '>'
                  when op = 'gte' then '>='
                  when op = 'in' then '= any'
                  else 'UNKNOWN OP'
              end
          );
          res boolean;
      begin
          execute format(
              'select %L::'|| type_::text || ' ' || op_symbol
              || ' ( %L::'
              || (
                  case
                      when op = 'in' then type_::text || '[]'
                      else type_::text end
              )
              || ')', val_1, val_2) into res;
          return res;
      end;
      $$;


ALTER FUNCTION realtime.check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text) OWNER TO supabase_admin;

--
-- Name: is_visible_through_filters(realtime.wal_column[], realtime.user_defined_filter[]); Type: FUNCTION; Schema: realtime; Owner: supabase_admin
--

CREATE FUNCTION realtime.is_visible_through_filters(columns realtime.wal_column[], filters realtime.user_defined_filter[]) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $_$
    /*
    Should the record be visible (true) or filtered out (false) after *filters* are applied
    */
        select
            -- Default to allowed when no filters present
            $2 is null -- no filters. this should not happen because subscriptions has a default
            or array_length($2, 1) is null -- array length of an empty array is null
            or bool_and(
                coalesce(
                    realtime.check_equality_op(
                        op:=f.op,
                        type_:=coalesce(
                            col.type_oid::regtype, -- null when wal2json version <= 2.4
                            col.type_name::regtype
                        ),
                        -- cast jsonb to text
                        val_1:=col.value #>> '{}',
                        val_2:=f.value
                    ),
                    false -- if null, filter does not match
                )
            )
        from
            unnest(filters) f
            join unnest(columns) col
                on f.column_name = col.name;
    $_$;


ALTER FUNCTION realtime.is_visible_through_filters(columns realtime.wal_column[], filters realtime.user_defined_filter[]) OWNER TO supabase_admin;

--
-- Name: list_changes(name, name, integer, integer); Type: FUNCTION; Schema: realtime; Owner: supabase_admin
--

CREATE FUNCTION realtime.list_changes(publication name, slot_name name, max_changes integer, max_record_bytes integer) RETURNS SETOF realtime.wal_rls
    LANGUAGE sql
    SET log_min_messages TO 'fatal'
    AS $$
      with pub as (
        select
          concat_ws(
            ',',
            case when bool_or(pubinsert) then 'insert' else null end,
            case when bool_or(pubupdate) then 'update' else null end,
            case when bool_or(pubdelete) then 'delete' else null end
          ) as w2j_actions,
          coalesce(
            string_agg(
              realtime.quote_wal2json(format('%I.%I', schemaname, tablename)::regclass),
              ','
            ) filter (where ppt.tablename is not null and ppt.tablename not like '% %'),
            ''
          ) w2j_add_tables
        from
          pg_publication pp
          left join pg_publication_tables ppt
            on pp.pubname = ppt.pubname
        where
          pp.pubname = publication
        group by
          pp.pubname
        limit 1
      ),
      w2j as (
        select
          x.*, pub.w2j_add_tables
        from
          pub,
          pg_logical_slot_get_changes(
            slot_name, null, max_changes,
            'include-pk', 'true',
            'include-transaction', 'false',
            'include-timestamp', 'true',
            'include-type-oids', 'true',
            'format-version', '2',
            'actions', pub.w2j_actions,
            'add-tables', pub.w2j_add_tables
          ) x
      )
      select
        xyz.wal,
        xyz.is_rls_enabled,
        xyz.subscription_ids,
        xyz.errors
      from
        w2j,
        realtime.apply_rls(
          wal := w2j.data::jsonb,
          max_record_bytes := max_record_bytes
        ) xyz(wal, is_rls_enabled, subscription_ids, errors)
      where
        w2j.w2j_add_tables <> ''
        and xyz.subscription_ids[1] is not null
    $$;


ALTER FUNCTION realtime.list_changes(publication name, slot_name name, max_changes integer, max_record_bytes integer) OWNER TO supabase_admin;

--
-- Name: quote_wal2json(regclass); Type: FUNCTION; Schema: realtime; Owner: supabase_admin
--

CREATE FUNCTION realtime.quote_wal2json(entity regclass) RETURNS text
    LANGUAGE sql IMMUTABLE STRICT
    AS $$
      select
        (
          select string_agg('' || ch,'')
          from unnest(string_to_array(nsp.nspname::text, null)) with ordinality x(ch, idx)
          where
            not (x.idx = 1 and x.ch = '"')
            and not (
              x.idx = array_length(string_to_array(nsp.nspname::text, null), 1)
              and x.ch = '"'
            )
        )
        || '.'
        || (
          select string_agg('' || ch,'')
          from unnest(string_to_array(pc.relname::text, null)) with ordinality x(ch, idx)
          where
            not (x.idx = 1 and x.ch = '"')
            and not (
              x.idx = array_length(string_to_array(nsp.nspname::text, null), 1)
              and x.ch = '"'
            )
          )
      from
        pg_class pc
        join pg_namespace nsp
          on pc.relnamespace = nsp.oid
      where
        pc.oid = entity
    $$;


ALTER FUNCTION realtime.quote_wal2json(entity regclass) OWNER TO supabase_admin;

--
-- Name: send(jsonb, text, text, boolean); Type: FUNCTION; Schema: realtime; Owner: supabase_admin
--

CREATE FUNCTION realtime.send(payload jsonb, event text, topic text, private boolean DEFAULT true) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  generated_id uuid;
  final_payload jsonb;
BEGIN
  BEGIN
    -- Generate a new UUID for the id
    generated_id := gen_random_uuid();

    -- Check if payload has an 'id' key, if not, add the generated UUID
    IF payload ? 'id' THEN
      final_payload := payload;
    ELSE
      final_payload := jsonb_set(payload, '{id}', to_jsonb(generated_id));
    END IF;

    -- Set the topic configuration
    EXECUTE format('SET LOCAL realtime.topic TO %L', topic);

    -- Attempt to insert the message
    INSERT INTO realtime.messages (id, payload, event, topic, private, extension)
    VALUES (generated_id, final_payload, event, topic, private, 'broadcast');
  EXCEPTION
    WHEN OTHERS THEN
      -- Capture and notify the error
      RAISE WARNING 'ErrorSendingBroadcastMessage: %', SQLERRM;
  END;
END;
$$;


ALTER FUNCTION realtime.send(payload jsonb, event text, topic text, private boolean) OWNER TO supabase_admin;

--
-- Name: subscription_check_filters(); Type: FUNCTION; Schema: realtime; Owner: supabase_admin
--

CREATE FUNCTION realtime.subscription_check_filters() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    /*
    Validates that the user defined filters for a subscription:
    - refer to valid columns that the claimed role may access
    - values are coercable to the correct column type
    */
    declare
        col_names text[] = coalesce(
                array_agg(c.column_name order by c.ordinal_position),
                '{}'::text[]
            )
            from
                information_schema.columns c
            where
                format('%I.%I', c.table_schema, c.table_name)::regclass = new.entity
                and pg_catalog.has_column_privilege(
                    (new.claims ->> 'role'),
                    format('%I.%I', c.table_schema, c.table_name)::regclass,
                    c.column_name,
                    'SELECT'
                );
        filter realtime.user_defined_filter;
        col_type regtype;

        in_val jsonb;
    begin
        for filter in select * from unnest(new.filters) loop
            -- Filtered column is valid
            if not filter.column_name = any(col_names) then
                raise exception 'invalid column for filter %', filter.column_name;
            end if;

            -- Type is sanitized and safe for string interpolation
            col_type = (
                select atttypid::regtype
                from pg_catalog.pg_attribute
                where attrelid = new.entity
                      and attname = filter.column_name
            );
            if col_type is null then
                raise exception 'failed to lookup type for column %', filter.column_name;
            end if;

            -- Set maximum number of entries for in filter
            if filter.op = 'in'::realtime.equality_op then
                in_val = realtime.cast(filter.value, (col_type::text || '[]')::regtype);
                if coalesce(jsonb_array_length(in_val), 0) > 100 then
                    raise exception 'too many values for `in` filter. Maximum 100';
                end if;
            else
                -- raises an exception if value is not coercable to type
                perform realtime.cast(filter.value, col_type);
            end if;

        end loop;

        -- Apply consistent order to filters so the unique constraint on
        -- (subscription_id, entity, filters) can't be tricked by a different filter order
        new.filters = coalesce(
            array_agg(f order by f.column_name, f.op, f.value),
            '{}'
        ) from unnest(new.filters) f;

        return new;
    end;
    $$;


ALTER FUNCTION realtime.subscription_check_filters() OWNER TO supabase_admin;

--
-- Name: to_regrole(text); Type: FUNCTION; Schema: realtime; Owner: supabase_admin
--

CREATE FUNCTION realtime.to_regrole(role_name text) RETURNS regrole
    LANGUAGE sql IMMUTABLE
    AS $$ select role_name::regrole $$;


ALTER FUNCTION realtime.to_regrole(role_name text) OWNER TO supabase_admin;

--
-- Name: topic(); Type: FUNCTION; Schema: realtime; Owner: supabase_realtime_admin
--

CREATE FUNCTION realtime.topic() RETURNS text
    LANGUAGE sql STABLE
    AS $$
select nullif(current_setting('realtime.topic', true), '')::text;
$$;


ALTER FUNCTION realtime.topic() OWNER TO supabase_realtime_admin;

--
-- Name: can_insert_object(text, text, uuid, jsonb); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.can_insert_object(bucketid text, name text, owner uuid, metadata jsonb) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO "storage"."objects" ("bucket_id", "name", "owner", "metadata") VALUES (bucketid, name, owner, metadata);
  -- hack to rollback the successful insert
  RAISE sqlstate 'PT200' using
  message = 'ROLLBACK',
  detail = 'rollback successful insert';
END
$$;


ALTER FUNCTION storage.can_insert_object(bucketid text, name text, owner uuid, metadata jsonb) OWNER TO supabase_storage_admin;

--
-- Name: delete_leaf_prefixes(text[], text[]); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.delete_leaf_prefixes(bucket_ids text[], names text[]) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_rows_deleted integer;
BEGIN
    LOOP
        WITH candidates AS (
            SELECT DISTINCT
                t.bucket_id,
                unnest(storage.get_prefixes(t.name)) AS name
            FROM unnest(bucket_ids, names) AS t(bucket_id, name)
        ),
        uniq AS (
             SELECT
                 bucket_id,
                 name,
                 storage.get_level(name) AS level
             FROM candidates
             WHERE name <> ''
             GROUP BY bucket_id, name
        ),
        leaf AS (
             SELECT
                 p.bucket_id,
                 p.name,
                 p.level
             FROM storage.prefixes AS p
                  JOIN uniq AS u
                       ON u.bucket_id = p.bucket_id
                           AND u.name = p.name
                           AND u.level = p.level
             WHERE NOT EXISTS (
                 SELECT 1
                 FROM storage.objects AS o
                 WHERE o.bucket_id = p.bucket_id
                   AND o.level = p.level + 1
                   AND o.name COLLATE "C" LIKE p.name || '/%'
             )
             AND NOT EXISTS (
                 SELECT 1
                 FROM storage.prefixes AS c
                 WHERE c.bucket_id = p.bucket_id
                   AND c.level = p.level + 1
                   AND c.name COLLATE "C" LIKE p.name || '/%'
             )
        )
        DELETE
        FROM storage.prefixes AS p
            USING leaf AS l
        WHERE p.bucket_id = l.bucket_id
          AND p.name = l.name
          AND p.level = l.level;

        GET DIAGNOSTICS v_rows_deleted = ROW_COUNT;
        EXIT WHEN v_rows_deleted = 0;
    END LOOP;
END;
$$;


ALTER FUNCTION storage.delete_leaf_prefixes(bucket_ids text[], names text[]) OWNER TO supabase_storage_admin;

--
-- Name: enforce_bucket_name_length(); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.enforce_bucket_name_length() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
    if length(new.name) > 100 then
        raise exception 'bucket name "%" is too long (% characters). Max is 100.', new.name, length(new.name);
    end if;
    return new;
end;
$$;


ALTER FUNCTION storage.enforce_bucket_name_length() OWNER TO supabase_storage_admin;

--
-- Name: extension(text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.extension(name text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
    _parts text[];
    _filename text;
BEGIN
    SELECT string_to_array(name, '/') INTO _parts;
    SELECT _parts[array_length(_parts,1)] INTO _filename;
    RETURN reverse(split_part(reverse(_filename), '.', 1));
END
$$;


ALTER FUNCTION storage.extension(name text) OWNER TO supabase_storage_admin;

--
-- Name: filename(text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.filename(name text) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
_parts text[];
BEGIN
	select string_to_array(name, '/') into _parts;
	return _parts[array_length(_parts,1)];
END
$$;


ALTER FUNCTION storage.filename(name text) OWNER TO supabase_storage_admin;

--
-- Name: foldername(text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.foldername(name text) RETURNS text[]
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
    _parts text[];
BEGIN
    -- Split on "/" to get path segments
    SELECT string_to_array(name, '/') INTO _parts;
    -- Return everything except the last segment
    RETURN _parts[1 : array_length(_parts,1) - 1];
END
$$;


ALTER FUNCTION storage.foldername(name text) OWNER TO supabase_storage_admin;

--
-- Name: get_common_prefix(text, text, text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.get_common_prefix(p_key text, p_prefix text, p_delimiter text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
SELECT CASE
    WHEN position(p_delimiter IN substring(p_key FROM length(p_prefix) + 1)) > 0
    THEN left(p_key, length(p_prefix) + position(p_delimiter IN substring(p_key FROM length(p_prefix) + 1)))
    ELSE NULL
END;
$$;


ALTER FUNCTION storage.get_common_prefix(p_key text, p_prefix text, p_delimiter text) OWNER TO supabase_storage_admin;

--
-- Name: get_level(text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.get_level(name text) RETURNS integer
    LANGUAGE sql IMMUTABLE STRICT
    AS $$
SELECT array_length(string_to_array("name", '/'), 1);
$$;


ALTER FUNCTION storage.get_level(name text) OWNER TO supabase_storage_admin;

--
-- Name: get_prefix(text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.get_prefix(name text) RETURNS text
    LANGUAGE sql IMMUTABLE STRICT
    AS $_$
SELECT
    CASE WHEN strpos("name", '/') > 0 THEN
             regexp_replace("name", '[\/]{1}[^\/]+\/?$', '')
         ELSE
             ''
        END;
$_$;


ALTER FUNCTION storage.get_prefix(name text) OWNER TO supabase_storage_admin;

--
-- Name: get_prefixes(text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.get_prefixes(name text) RETURNS text[]
    LANGUAGE plpgsql IMMUTABLE STRICT
    AS $$
DECLARE
    parts text[];
    prefixes text[];
    prefix text;
BEGIN
    -- Split the name into parts by '/'
    parts := string_to_array("name", '/');
    prefixes := '{}';

    -- Construct the prefixes, stopping one level below the last part
    FOR i IN 1..array_length(parts, 1) - 1 LOOP
            prefix := array_to_string(parts[1:i], '/');
            prefixes := array_append(prefixes, prefix);
    END LOOP;

    RETURN prefixes;
END;
$$;


ALTER FUNCTION storage.get_prefixes(name text) OWNER TO supabase_storage_admin;

--
-- Name: get_size_by_bucket(); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.get_size_by_bucket() RETURNS TABLE(size bigint, bucket_id text)
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    return query
        select sum((metadata->>'size')::bigint) as size, obj.bucket_id
        from "storage".objects as obj
        group by obj.bucket_id;
END
$$;


ALTER FUNCTION storage.get_size_by_bucket() OWNER TO supabase_storage_admin;

--
-- Name: list_multipart_uploads_with_delimiter(text, text, text, integer, text, text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.list_multipart_uploads_with_delimiter(bucket_id text, prefix_param text, delimiter_param text, max_keys integer DEFAULT 100, next_key_token text DEFAULT ''::text, next_upload_token text DEFAULT ''::text) RETURNS TABLE(key text, id text, created_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $_$
BEGIN
    RETURN QUERY EXECUTE
        'SELECT DISTINCT ON(key COLLATE "C") * from (
            SELECT
                CASE
                    WHEN position($2 IN substring(key from length($1) + 1)) > 0 THEN
                        substring(key from 1 for length($1) + position($2 IN substring(key from length($1) + 1)))
                    ELSE
                        key
                END AS key, id, created_at
            FROM
                storage.s3_multipart_uploads
            WHERE
                bucket_id = $5 AND
                key ILIKE $1 || ''%'' AND
                CASE
                    WHEN $4 != '''' AND $6 = '''' THEN
                        CASE
                            WHEN position($2 IN substring(key from length($1) + 1)) > 0 THEN
                                substring(key from 1 for length($1) + position($2 IN substring(key from length($1) + 1))) COLLATE "C" > $4
                            ELSE
                                key COLLATE "C" > $4
                            END
                    ELSE
                        true
                END AND
                CASE
                    WHEN $6 != '''' THEN
                        id COLLATE "C" > $6
                    ELSE
                        true
                    END
            ORDER BY
                key COLLATE "C" ASC, created_at ASC) as e order by key COLLATE "C" LIMIT $3'
        USING prefix_param, delimiter_param, max_keys, next_key_token, bucket_id, next_upload_token;
END;
$_$;


ALTER FUNCTION storage.list_multipart_uploads_with_delimiter(bucket_id text, prefix_param text, delimiter_param text, max_keys integer, next_key_token text, next_upload_token text) OWNER TO supabase_storage_admin;

--
-- Name: list_objects_with_delimiter(text, text, text, integer, text, text, text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.list_objects_with_delimiter(_bucket_id text, prefix_param text, delimiter_param text, max_keys integer DEFAULT 100, start_after text DEFAULT ''::text, next_token text DEFAULT ''::text, sort_order text DEFAULT 'asc'::text) RETURNS TABLE(name text, id uuid, metadata jsonb, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone)
    LANGUAGE plpgsql STABLE
    AS $_$
DECLARE
    v_peek_name TEXT;
    v_current RECORD;
    v_common_prefix TEXT;

    -- Configuration
    v_is_asc BOOLEAN;
    v_prefix TEXT;
    v_start TEXT;
    v_upper_bound TEXT;
    v_file_batch_size INT;

    -- Seek state
    v_next_seek TEXT;
    v_count INT := 0;

    -- Dynamic SQL for batch query only
    v_batch_query TEXT;

BEGIN
    -- ========================================================================
    -- INITIALIZATION
    -- ========================================================================
    v_is_asc := lower(coalesce(sort_order, 'asc')) = 'asc';
    v_prefix := coalesce(prefix_param, '');
    v_start := CASE WHEN coalesce(next_token, '') <> '' THEN next_token ELSE coalesce(start_after, '') END;
    v_file_batch_size := LEAST(GREATEST(max_keys * 2, 100), 1000);

    -- Calculate upper bound for prefix filtering (bytewise, using COLLATE "C")
    IF v_prefix = '' THEN
        v_upper_bound := NULL;
    ELSIF right(v_prefix, 1) = delimiter_param THEN
        v_upper_bound := left(v_prefix, -1) || chr(ascii(delimiter_param) + 1);
    ELSE
        v_upper_bound := left(v_prefix, -1) || chr(ascii(right(v_prefix, 1)) + 1);
    END IF;

    -- Build batch query (dynamic SQL - called infrequently, amortized over many rows)
    IF v_is_asc THEN
        IF v_upper_bound IS NOT NULL THEN
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND o.name COLLATE "C" >= $2 ' ||
                'AND o.name COLLATE "C" < $3 ORDER BY o.name COLLATE "C" ASC LIMIT $4';
        ELSE
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND o.name COLLATE "C" >= $2 ' ||
                'ORDER BY o.name COLLATE "C" ASC LIMIT $4';
        END IF;
    ELSE
        IF v_upper_bound IS NOT NULL THEN
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND o.name COLLATE "C" < $2 ' ||
                'AND o.name COLLATE "C" >= $3 ORDER BY o.name COLLATE "C" DESC LIMIT $4';
        ELSE
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND o.name COLLATE "C" < $2 ' ||
                'ORDER BY o.name COLLATE "C" DESC LIMIT $4';
        END IF;
    END IF;

    -- ========================================================================
    -- SEEK INITIALIZATION: Determine starting position
    -- ========================================================================
    IF v_start = '' THEN
        IF v_is_asc THEN
            v_next_seek := v_prefix;
        ELSE
            -- DESC without cursor: find the last item in range
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_next_seek FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" >= v_prefix AND o.name COLLATE "C" < v_upper_bound
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            ELSIF v_prefix <> '' THEN
                SELECT o.name INTO v_next_seek FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" >= v_prefix
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            ELSE
                SELECT o.name INTO v_next_seek FROM storage.objects o
                WHERE o.bucket_id = _bucket_id
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            END IF;

            IF v_next_seek IS NOT NULL THEN
                v_next_seek := v_next_seek || delimiter_param;
            ELSE
                RETURN;
            END IF;
        END IF;
    ELSE
        -- Cursor provided: determine if it refers to a folder or leaf
        IF EXISTS (
            SELECT 1 FROM storage.objects o
            WHERE o.bucket_id = _bucket_id
              AND o.name COLLATE "C" LIKE v_start || delimiter_param || '%'
            LIMIT 1
        ) THEN
            -- Cursor refers to a folder
            IF v_is_asc THEN
                v_next_seek := v_start || chr(ascii(delimiter_param) + 1);
            ELSE
                v_next_seek := v_start || delimiter_param;
            END IF;
        ELSE
            -- Cursor refers to a leaf object
            IF v_is_asc THEN
                v_next_seek := v_start || delimiter_param;
            ELSE
                v_next_seek := v_start;
            END IF;
        END IF;
    END IF;

    -- ========================================================================
    -- MAIN LOOP: Hybrid peek-then-batch algorithm
    -- Uses STATIC SQL for peek (hot path) and DYNAMIC SQL for batch
    -- ========================================================================
    LOOP
        EXIT WHEN v_count >= max_keys;

        -- STEP 1: PEEK using STATIC SQL (plan cached, very fast)
        IF v_is_asc THEN
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" >= v_next_seek AND o.name COLLATE "C" < v_upper_bound
                ORDER BY o.name COLLATE "C" ASC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" >= v_next_seek
                ORDER BY o.name COLLATE "C" ASC LIMIT 1;
            END IF;
        ELSE
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" < v_next_seek AND o.name COLLATE "C" >= v_prefix
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            ELSIF v_prefix <> '' THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" < v_next_seek AND o.name COLLATE "C" >= v_prefix
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" < v_next_seek
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            END IF;
        END IF;

        EXIT WHEN v_peek_name IS NULL;

        -- STEP 2: Check if this is a FOLDER or FILE
        v_common_prefix := storage.get_common_prefix(v_peek_name, v_prefix, delimiter_param);

        IF v_common_prefix IS NOT NULL THEN
            -- FOLDER: Emit and skip to next folder (no heap access needed)
            name := rtrim(v_common_prefix, delimiter_param);
            id := NULL;
            updated_at := NULL;
            created_at := NULL;
            last_accessed_at := NULL;
            metadata := NULL;
            RETURN NEXT;
            v_count := v_count + 1;

            -- Advance seek past the folder range
            IF v_is_asc THEN
                v_next_seek := left(v_common_prefix, -1) || chr(ascii(delimiter_param) + 1);
            ELSE
                v_next_seek := v_common_prefix;
            END IF;
        ELSE
            -- FILE: Batch fetch using DYNAMIC SQL (overhead amortized over many rows)
            -- For ASC: upper_bound is the exclusive upper limit (< condition)
            -- For DESC: prefix is the inclusive lower limit (>= condition)
            FOR v_current IN EXECUTE v_batch_query USING _bucket_id, v_next_seek,
                CASE WHEN v_is_asc THEN COALESCE(v_upper_bound, v_prefix) ELSE v_prefix END, v_file_batch_size
            LOOP
                v_common_prefix := storage.get_common_prefix(v_current.name, v_prefix, delimiter_param);

                IF v_common_prefix IS NOT NULL THEN
                    -- Hit a folder: exit batch, let peek handle it
                    v_next_seek := v_current.name;
                    EXIT;
                END IF;

                -- Emit file
                name := v_current.name;
                id := v_current.id;
                updated_at := v_current.updated_at;
                created_at := v_current.created_at;
                last_accessed_at := v_current.last_accessed_at;
                metadata := v_current.metadata;
                RETURN NEXT;
                v_count := v_count + 1;

                -- Advance seek past this file
                IF v_is_asc THEN
                    v_next_seek := v_current.name || delimiter_param;
                ELSE
                    v_next_seek := v_current.name;
                END IF;

                EXIT WHEN v_count >= max_keys;
            END LOOP;
        END IF;
    END LOOP;
END;
$_$;


ALTER FUNCTION storage.list_objects_with_delimiter(_bucket_id text, prefix_param text, delimiter_param text, max_keys integer, start_after text, next_token text, sort_order text) OWNER TO supabase_storage_admin;

--
-- Name: operation(); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.operation() RETURNS text
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    RETURN current_setting('storage.operation', true);
END;
$$;


ALTER FUNCTION storage.operation() OWNER TO supabase_storage_admin;

--
-- Name: protect_delete(); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.protect_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Check if storage.allow_delete_query is set to 'true'
    IF COALESCE(current_setting('storage.allow_delete_query', true), 'false') != 'true' THEN
        RAISE EXCEPTION 'Direct deletion from storage tables is not allowed. Use the Storage API instead.'
            USING HINT = 'This prevents accidental data loss from orphaned objects.',
                  ERRCODE = '42501';
    END IF;
    RETURN NULL;
END;
$$;


ALTER FUNCTION storage.protect_delete() OWNER TO supabase_storage_admin;

--
-- Name: search(text, text, integer, integer, integer, text, text, text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.search(prefix text, bucketname text, limits integer DEFAULT 100, levels integer DEFAULT 1, offsets integer DEFAULT 0, search text DEFAULT ''::text, sortcolumn text DEFAULT 'name'::text, sortorder text DEFAULT 'asc'::text) RETURNS TABLE(name text, id uuid, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone, metadata jsonb)
    LANGUAGE plpgsql STABLE
    AS $_$
DECLARE
    v_peek_name TEXT;
    v_current RECORD;
    v_common_prefix TEXT;
    v_delimiter CONSTANT TEXT := '/';

    -- Configuration
    v_limit INT;
    v_prefix TEXT;
    v_prefix_lower TEXT;
    v_is_asc BOOLEAN;
    v_order_by TEXT;
    v_sort_order TEXT;
    v_upper_bound TEXT;
    v_file_batch_size INT;

    -- Dynamic SQL for batch query only
    v_batch_query TEXT;

    -- Seek state
    v_next_seek TEXT;
    v_count INT := 0;
    v_skipped INT := 0;
BEGIN
    -- ========================================================================
    -- INITIALIZATION
    -- ========================================================================
    v_limit := LEAST(coalesce(limits, 100), 1500);
    v_prefix := coalesce(prefix, '') || coalesce(search, '');
    v_prefix_lower := lower(v_prefix);
    v_is_asc := lower(coalesce(sortorder, 'asc')) = 'asc';
    v_file_batch_size := LEAST(GREATEST(v_limit * 2, 100), 1000);

    -- Validate sort column
    CASE lower(coalesce(sortcolumn, 'name'))
        WHEN 'name' THEN v_order_by := 'name';
        WHEN 'updated_at' THEN v_order_by := 'updated_at';
        WHEN 'created_at' THEN v_order_by := 'created_at';
        WHEN 'last_accessed_at' THEN v_order_by := 'last_accessed_at';
        ELSE v_order_by := 'name';
    END CASE;

    v_sort_order := CASE WHEN v_is_asc THEN 'asc' ELSE 'desc' END;

    -- ========================================================================
    -- NON-NAME SORTING: Use path_tokens approach (unchanged)
    -- ========================================================================
    IF v_order_by != 'name' THEN
        RETURN QUERY EXECUTE format(
            $sql$
            WITH folders AS (
                SELECT path_tokens[$1] AS folder
                FROM storage.objects
                WHERE objects.name ILIKE $2 || '%%'
                  AND bucket_id = $3
                  AND array_length(objects.path_tokens, 1) <> $1
                GROUP BY folder
                ORDER BY folder %s
            )
            (SELECT folder AS "name",
                   NULL::uuid AS id,
                   NULL::timestamptz AS updated_at,
                   NULL::timestamptz AS created_at,
                   NULL::timestamptz AS last_accessed_at,
                   NULL::jsonb AS metadata FROM folders)
            UNION ALL
            (SELECT path_tokens[$1] AS "name",
                   id, updated_at, created_at, last_accessed_at, metadata
             FROM storage.objects
             WHERE objects.name ILIKE $2 || '%%'
               AND bucket_id = $3
               AND array_length(objects.path_tokens, 1) = $1
             ORDER BY %I %s)
            LIMIT $4 OFFSET $5
            $sql$, v_sort_order, v_order_by, v_sort_order
        ) USING levels, v_prefix, bucketname, v_limit, offsets;
        RETURN;
    END IF;

    -- ========================================================================
    -- NAME SORTING: Hybrid skip-scan with batch optimization
    -- ========================================================================

    -- Calculate upper bound for prefix filtering
    IF v_prefix_lower = '' THEN
        v_upper_bound := NULL;
    ELSIF right(v_prefix_lower, 1) = v_delimiter THEN
        v_upper_bound := left(v_prefix_lower, -1) || chr(ascii(v_delimiter) + 1);
    ELSE
        v_upper_bound := left(v_prefix_lower, -1) || chr(ascii(right(v_prefix_lower, 1)) + 1);
    END IF;

    -- Build batch query (dynamic SQL - called infrequently, amortized over many rows)
    IF v_is_asc THEN
        IF v_upper_bound IS NOT NULL THEN
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" >= $2 ' ||
                'AND lower(o.name) COLLATE "C" < $3 ORDER BY lower(o.name) COLLATE "C" ASC LIMIT $4';
        ELSE
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" >= $2 ' ||
                'ORDER BY lower(o.name) COLLATE "C" ASC LIMIT $4';
        END IF;
    ELSE
        IF v_upper_bound IS NOT NULL THEN
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" < $2 ' ||
                'AND lower(o.name) COLLATE "C" >= $3 ORDER BY lower(o.name) COLLATE "C" DESC LIMIT $4';
        ELSE
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" < $2 ' ||
                'ORDER BY lower(o.name) COLLATE "C" DESC LIMIT $4';
        END IF;
    END IF;

    -- Initialize seek position
    IF v_is_asc THEN
        v_next_seek := v_prefix_lower;
    ELSE
        -- DESC: find the last item in range first (static SQL)
        IF v_upper_bound IS NOT NULL THEN
            SELECT o.name INTO v_peek_name FROM storage.objects o
            WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_prefix_lower AND lower(o.name) COLLATE "C" < v_upper_bound
            ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
        ELSIF v_prefix_lower <> '' THEN
            SELECT o.name INTO v_peek_name FROM storage.objects o
            WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_prefix_lower
            ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
        ELSE
            SELECT o.name INTO v_peek_name FROM storage.objects o
            WHERE o.bucket_id = bucketname
            ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
        END IF;

        IF v_peek_name IS NOT NULL THEN
            v_next_seek := lower(v_peek_name) || v_delimiter;
        ELSE
            RETURN;
        END IF;
    END IF;

    -- ========================================================================
    -- MAIN LOOP: Hybrid peek-then-batch algorithm
    -- Uses STATIC SQL for peek (hot path) and DYNAMIC SQL for batch
    -- ========================================================================
    LOOP
        EXIT WHEN v_count >= v_limit;

        -- STEP 1: PEEK using STATIC SQL (plan cached, very fast)
        IF v_is_asc THEN
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_next_seek AND lower(o.name) COLLATE "C" < v_upper_bound
                ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_next_seek
                ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1;
            END IF;
        ELSE
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" < v_next_seek AND lower(o.name) COLLATE "C" >= v_prefix_lower
                ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
            ELSIF v_prefix_lower <> '' THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" < v_next_seek AND lower(o.name) COLLATE "C" >= v_prefix_lower
                ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" < v_next_seek
                ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
            END IF;
        END IF;

        EXIT WHEN v_peek_name IS NULL;

        -- STEP 2: Check if this is a FOLDER or FILE
        v_common_prefix := storage.get_common_prefix(lower(v_peek_name), v_prefix_lower, v_delimiter);

        IF v_common_prefix IS NOT NULL THEN
            -- FOLDER: Handle offset, emit if needed, skip to next folder
            IF v_skipped < offsets THEN
                v_skipped := v_skipped + 1;
            ELSE
                name := split_part(rtrim(storage.get_common_prefix(v_peek_name, v_prefix, v_delimiter), v_delimiter), v_delimiter, levels);
                id := NULL;
                updated_at := NULL;
                created_at := NULL;
                last_accessed_at := NULL;
                metadata := NULL;
                RETURN NEXT;
                v_count := v_count + 1;
            END IF;

            -- Advance seek past the folder range
            IF v_is_asc THEN
                v_next_seek := lower(left(v_common_prefix, -1)) || chr(ascii(v_delimiter) + 1);
            ELSE
                v_next_seek := lower(v_common_prefix);
            END IF;
        ELSE
            -- FILE: Batch fetch using DYNAMIC SQL (overhead amortized over many rows)
            -- For ASC: upper_bound is the exclusive upper limit (< condition)
            -- For DESC: prefix_lower is the inclusive lower limit (>= condition)
            FOR v_current IN EXECUTE v_batch_query
                USING bucketname, v_next_seek,
                    CASE WHEN v_is_asc THEN COALESCE(v_upper_bound, v_prefix_lower) ELSE v_prefix_lower END, v_file_batch_size
            LOOP
                v_common_prefix := storage.get_common_prefix(lower(v_current.name), v_prefix_lower, v_delimiter);

                IF v_common_prefix IS NOT NULL THEN
                    -- Hit a folder: exit batch, let peek handle it
                    v_next_seek := lower(v_current.name);
                    EXIT;
                END IF;

                -- Handle offset skipping
                IF v_skipped < offsets THEN
                    v_skipped := v_skipped + 1;
                ELSE
                    -- Emit file
                    name := split_part(v_current.name, v_delimiter, levels);
                    id := v_current.id;
                    updated_at := v_current.updated_at;
                    created_at := v_current.created_at;
                    last_accessed_at := v_current.last_accessed_at;
                    metadata := v_current.metadata;
                    RETURN NEXT;
                    v_count := v_count + 1;
                END IF;

                -- Advance seek past this file
                IF v_is_asc THEN
                    v_next_seek := lower(v_current.name) || v_delimiter;
                ELSE
                    v_next_seek := lower(v_current.name);
                END IF;

                EXIT WHEN v_count >= v_limit;
            END LOOP;
        END IF;
    END LOOP;
END;
$_$;


ALTER FUNCTION storage.search(prefix text, bucketname text, limits integer, levels integer, offsets integer, search text, sortcolumn text, sortorder text) OWNER TO supabase_storage_admin;

--
-- Name: search_by_timestamp(text, text, integer, integer, text, text, text, text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.search_by_timestamp(p_prefix text, p_bucket_id text, p_limit integer, p_level integer, p_start_after text, p_sort_order text, p_sort_column text, p_sort_column_after text) RETURNS TABLE(key text, name text, id uuid, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone, metadata jsonb)
    LANGUAGE plpgsql STABLE
    AS $_$
DECLARE
    v_cursor_op text;
    v_query text;
    v_prefix text;
BEGIN
    v_prefix := coalesce(p_prefix, '');

    IF p_sort_order = 'asc' THEN
        v_cursor_op := '>';
    ELSE
        v_cursor_op := '<';
    END IF;

    v_query := format($sql$
        WITH raw_objects AS (
            SELECT
                o.name AS obj_name,
                o.id AS obj_id,
                o.updated_at AS obj_updated_at,
                o.created_at AS obj_created_at,
                o.last_accessed_at AS obj_last_accessed_at,
                o.metadata AS obj_metadata,
                storage.get_common_prefix(o.name, $1, '/') AS common_prefix
            FROM storage.objects o
            WHERE o.bucket_id = $2
              AND o.name COLLATE "C" LIKE $1 || '%%'
        ),
        -- Aggregate common prefixes (folders)
        -- Both created_at and updated_at use MIN(obj_created_at) to match the old prefixes table behavior
        aggregated_prefixes AS (
            SELECT
                rtrim(common_prefix, '/') AS name,
                NULL::uuid AS id,
                MIN(obj_created_at) AS updated_at,
                MIN(obj_created_at) AS created_at,
                NULL::timestamptz AS last_accessed_at,
                NULL::jsonb AS metadata,
                TRUE AS is_prefix
            FROM raw_objects
            WHERE common_prefix IS NOT NULL
            GROUP BY common_prefix
        ),
        leaf_objects AS (
            SELECT
                obj_name AS name,
                obj_id AS id,
                obj_updated_at AS updated_at,
                obj_created_at AS created_at,
                obj_last_accessed_at AS last_accessed_at,
                obj_metadata AS metadata,
                FALSE AS is_prefix
            FROM raw_objects
            WHERE common_prefix IS NULL
        ),
        combined AS (
            SELECT * FROM aggregated_prefixes
            UNION ALL
            SELECT * FROM leaf_objects
        ),
        filtered AS (
            SELECT *
            FROM combined
            WHERE (
                $5 = ''
                OR ROW(
                    date_trunc('milliseconds', %I),
                    name COLLATE "C"
                ) %s ROW(
                    COALESCE(NULLIF($6, '')::timestamptz, 'epoch'::timestamptz),
                    $5
                )
            )
        )
        SELECT
            split_part(name, '/', $3) AS key,
            name,
            id,
            updated_at,
            created_at,
            last_accessed_at,
            metadata
        FROM filtered
        ORDER BY
            COALESCE(date_trunc('milliseconds', %I), 'epoch'::timestamptz) %s,
            name COLLATE "C" %s
        LIMIT $4
    $sql$,
        p_sort_column,
        v_cursor_op,
        p_sort_column,
        p_sort_order,
        p_sort_order
    );

    RETURN QUERY EXECUTE v_query
    USING v_prefix, p_bucket_id, p_level, p_limit, p_start_after, p_sort_column_after;
END;
$_$;


ALTER FUNCTION storage.search_by_timestamp(p_prefix text, p_bucket_id text, p_limit integer, p_level integer, p_start_after text, p_sort_order text, p_sort_column text, p_sort_column_after text) OWNER TO supabase_storage_admin;

--
-- Name: search_legacy_v1(text, text, integer, integer, integer, text, text, text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.search_legacy_v1(prefix text, bucketname text, limits integer DEFAULT 100, levels integer DEFAULT 1, offsets integer DEFAULT 0, search text DEFAULT ''::text, sortcolumn text DEFAULT 'name'::text, sortorder text DEFAULT 'asc'::text) RETURNS TABLE(name text, id uuid, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone, metadata jsonb)
    LANGUAGE plpgsql STABLE
    AS $_$
declare
    v_order_by text;
    v_sort_order text;
begin
    case
        when sortcolumn = 'name' then
            v_order_by = 'name';
        when sortcolumn = 'updated_at' then
            v_order_by = 'updated_at';
        when sortcolumn = 'created_at' then
            v_order_by = 'created_at';
        when sortcolumn = 'last_accessed_at' then
            v_order_by = 'last_accessed_at';
        else
            v_order_by = 'name';
        end case;

    case
        when sortorder = 'asc' then
            v_sort_order = 'asc';
        when sortorder = 'desc' then
            v_sort_order = 'desc';
        else
            v_sort_order = 'asc';
        end case;

    v_order_by = v_order_by || ' ' || v_sort_order;

    return query execute
        'with folders as (
           select path_tokens[$1] as folder
           from storage.objects
             where objects.name ilike $2 || $3 || ''%''
               and bucket_id = $4
               and array_length(objects.path_tokens, 1) <> $1
           group by folder
           order by folder ' || v_sort_order || '
     )
     (select folder as "name",
            null as id,
            null as updated_at,
            null as created_at,
            null as last_accessed_at,
            null as metadata from folders)
     union all
     (select path_tokens[$1] as "name",
            id,
            updated_at,
            created_at,
            last_accessed_at,
            metadata
     from storage.objects
     where objects.name ilike $2 || $3 || ''%''
       and bucket_id = $4
       and array_length(objects.path_tokens, 1) = $1
     order by ' || v_order_by || ')
     limit $5
     offset $6' using levels, prefix, search, bucketname, limits, offsets;
end;
$_$;


ALTER FUNCTION storage.search_legacy_v1(prefix text, bucketname text, limits integer, levels integer, offsets integer, search text, sortcolumn text, sortorder text) OWNER TO supabase_storage_admin;

--
-- Name: search_v2(text, text, integer, integer, text, text, text, text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.search_v2(prefix text, bucket_name text, limits integer DEFAULT 100, levels integer DEFAULT 1, start_after text DEFAULT ''::text, sort_order text DEFAULT 'asc'::text, sort_column text DEFAULT 'name'::text, sort_column_after text DEFAULT ''::text) RETURNS TABLE(key text, name text, id uuid, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone, metadata jsonb)
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    v_sort_col text;
    v_sort_ord text;
    v_limit int;
BEGIN
    -- Cap limit to maximum of 1500 records
    v_limit := LEAST(coalesce(limits, 100), 1500);

    -- Validate and normalize sort_order
    v_sort_ord := lower(coalesce(sort_order, 'asc'));
    IF v_sort_ord NOT IN ('asc', 'desc') THEN
        v_sort_ord := 'asc';
    END IF;

    -- Validate and normalize sort_column
    v_sort_col := lower(coalesce(sort_column, 'name'));
    IF v_sort_col NOT IN ('name', 'updated_at', 'created_at') THEN
        v_sort_col := 'name';
    END IF;

    -- Route to appropriate implementation
    IF v_sort_col = 'name' THEN
        -- Use list_objects_with_delimiter for name sorting (most efficient: O(k * log n))
        RETURN QUERY
        SELECT
            split_part(l.name, '/', levels) AS key,
            l.name AS name,
            l.id,
            l.updated_at,
            l.created_at,
            l.last_accessed_at,
            l.metadata
        FROM storage.list_objects_with_delimiter(
            bucket_name,
            coalesce(prefix, ''),
            '/',
            v_limit,
            start_after,
            '',
            v_sort_ord
        ) l;
    ELSE
        -- Use aggregation approach for timestamp sorting
        -- Not efficient for large datasets but supports correct pagination
        RETURN QUERY SELECT * FROM storage.search_by_timestamp(
            prefix, bucket_name, v_limit, levels, start_after,
            v_sort_ord, v_sort_col, sort_column_after
        );
    END IF;
END;
$$;


ALTER FUNCTION storage.search_v2(prefix text, bucket_name text, limits integer, levels integer, start_after text, sort_order text, sort_column text, sort_column_after text) OWNER TO supabase_storage_admin;

--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW; 
END;
$$;


ALTER FUNCTION storage.update_updated_at_column() OWNER TO supabase_storage_admin;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: audit_log_entries; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.audit_log_entries (
    instance_id uuid,
    id uuid NOT NULL,
    payload json,
    created_at timestamp with time zone,
    ip_address character varying(64) DEFAULT ''::character varying NOT NULL
);


ALTER TABLE auth.audit_log_entries OWNER TO supabase_auth_admin;

--
-- Name: TABLE audit_log_entries; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.audit_log_entries IS 'Auth: Audit trail for user actions.';


--
-- Name: flow_state; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.flow_state (
    id uuid NOT NULL,
    user_id uuid,
    auth_code text,
    code_challenge_method auth.code_challenge_method,
    code_challenge text,
    provider_type text NOT NULL,
    provider_access_token text,
    provider_refresh_token text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    authentication_method text NOT NULL,
    auth_code_issued_at timestamp with time zone,
    invite_token text,
    referrer text,
    oauth_client_state_id uuid,
    linking_target_id uuid,
    email_optional boolean DEFAULT false NOT NULL
);


ALTER TABLE auth.flow_state OWNER TO supabase_auth_admin;

--
-- Name: TABLE flow_state; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.flow_state IS 'Stores metadata for all OAuth/SSO login flows';


--
-- Name: identities; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.identities (
    provider_id text NOT NULL,
    user_id uuid NOT NULL,
    identity_data jsonb NOT NULL,
    provider text NOT NULL,
    last_sign_in_at timestamp with time zone,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    email text GENERATED ALWAYS AS (lower((identity_data ->> 'email'::text))) STORED,
    id uuid DEFAULT gen_random_uuid() NOT NULL
);


ALTER TABLE auth.identities OWNER TO supabase_auth_admin;

--
-- Name: TABLE identities; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.identities IS 'Auth: Stores identities associated to a user.';


--
-- Name: COLUMN identities.email; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON COLUMN auth.identities.email IS 'Auth: Email is a generated column that references the optional email property in the identity_data';


--
-- Name: instances; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.instances (
    id uuid NOT NULL,
    uuid uuid,
    raw_base_config text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone
);


ALTER TABLE auth.instances OWNER TO supabase_auth_admin;

--
-- Name: TABLE instances; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.instances IS 'Auth: Manages users across multiple sites.';


--
-- Name: mfa_amr_claims; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.mfa_amr_claims (
    session_id uuid NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    authentication_method text NOT NULL,
    id uuid NOT NULL
);


ALTER TABLE auth.mfa_amr_claims OWNER TO supabase_auth_admin;

--
-- Name: TABLE mfa_amr_claims; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.mfa_amr_claims IS 'auth: stores authenticator method reference claims for multi factor authentication';


--
-- Name: mfa_challenges; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.mfa_challenges (
    id uuid NOT NULL,
    factor_id uuid NOT NULL,
    created_at timestamp with time zone NOT NULL,
    verified_at timestamp with time zone,
    ip_address inet NOT NULL,
    otp_code text,
    web_authn_session_data jsonb
);


ALTER TABLE auth.mfa_challenges OWNER TO supabase_auth_admin;

--
-- Name: TABLE mfa_challenges; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.mfa_challenges IS 'auth: stores metadata about challenge requests made';


--
-- Name: mfa_factors; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.mfa_factors (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    friendly_name text,
    factor_type auth.factor_type NOT NULL,
    status auth.factor_status NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    secret text,
    phone text,
    last_challenged_at timestamp with time zone,
    web_authn_credential jsonb,
    web_authn_aaguid uuid,
    last_webauthn_challenge_data jsonb
);


ALTER TABLE auth.mfa_factors OWNER TO supabase_auth_admin;

--
-- Name: TABLE mfa_factors; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.mfa_factors IS 'auth: stores metadata about factors';


--
-- Name: COLUMN mfa_factors.last_webauthn_challenge_data; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON COLUMN auth.mfa_factors.last_webauthn_challenge_data IS 'Stores the latest WebAuthn challenge data including attestation/assertion for customer verification';


--
-- Name: oauth_authorizations; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.oauth_authorizations (
    id uuid NOT NULL,
    authorization_id text NOT NULL,
    client_id uuid NOT NULL,
    user_id uuid,
    redirect_uri text NOT NULL,
    scope text NOT NULL,
    state text,
    resource text,
    code_challenge text,
    code_challenge_method auth.code_challenge_method,
    response_type auth.oauth_response_type DEFAULT 'code'::auth.oauth_response_type NOT NULL,
    status auth.oauth_authorization_status DEFAULT 'pending'::auth.oauth_authorization_status NOT NULL,
    authorization_code text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone DEFAULT (now() + '00:03:00'::interval) NOT NULL,
    approved_at timestamp with time zone,
    nonce text,
    CONSTRAINT oauth_authorizations_authorization_code_length CHECK ((char_length(authorization_code) <= 255)),
    CONSTRAINT oauth_authorizations_code_challenge_length CHECK ((char_length(code_challenge) <= 128)),
    CONSTRAINT oauth_authorizations_expires_at_future CHECK ((expires_at > created_at)),
    CONSTRAINT oauth_authorizations_nonce_length CHECK ((char_length(nonce) <= 255)),
    CONSTRAINT oauth_authorizations_redirect_uri_length CHECK ((char_length(redirect_uri) <= 2048)),
    CONSTRAINT oauth_authorizations_resource_length CHECK ((char_length(resource) <= 2048)),
    CONSTRAINT oauth_authorizations_scope_length CHECK ((char_length(scope) <= 4096)),
    CONSTRAINT oauth_authorizations_state_length CHECK ((char_length(state) <= 4096))
);


ALTER TABLE auth.oauth_authorizations OWNER TO supabase_auth_admin;

--
-- Name: oauth_client_states; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.oauth_client_states (
    id uuid NOT NULL,
    provider_type text NOT NULL,
    code_verifier text,
    created_at timestamp with time zone NOT NULL
);


ALTER TABLE auth.oauth_client_states OWNER TO supabase_auth_admin;

--
-- Name: TABLE oauth_client_states; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.oauth_client_states IS 'Stores OAuth states for third-party provider authentication flows where Supabase acts as the OAuth client.';


--
-- Name: oauth_clients; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.oauth_clients (
    id uuid NOT NULL,
    client_secret_hash text,
    registration_type auth.oauth_registration_type NOT NULL,
    redirect_uris text NOT NULL,
    grant_types text NOT NULL,
    client_name text,
    client_uri text,
    logo_uri text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    client_type auth.oauth_client_type DEFAULT 'confidential'::auth.oauth_client_type NOT NULL,
    token_endpoint_auth_method text NOT NULL,
    CONSTRAINT oauth_clients_client_name_length CHECK ((char_length(client_name) <= 1024)),
    CONSTRAINT oauth_clients_client_uri_length CHECK ((char_length(client_uri) <= 2048)),
    CONSTRAINT oauth_clients_logo_uri_length CHECK ((char_length(logo_uri) <= 2048)),
    CONSTRAINT oauth_clients_token_endpoint_auth_method_check CHECK ((token_endpoint_auth_method = ANY (ARRAY['client_secret_basic'::text, 'client_secret_post'::text, 'none'::text])))
);


ALTER TABLE auth.oauth_clients OWNER TO supabase_auth_admin;

--
-- Name: oauth_consents; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.oauth_consents (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    client_id uuid NOT NULL,
    scopes text NOT NULL,
    granted_at timestamp with time zone DEFAULT now() NOT NULL,
    revoked_at timestamp with time zone,
    CONSTRAINT oauth_consents_revoked_after_granted CHECK (((revoked_at IS NULL) OR (revoked_at >= granted_at))),
    CONSTRAINT oauth_consents_scopes_length CHECK ((char_length(scopes) <= 2048)),
    CONSTRAINT oauth_consents_scopes_not_empty CHECK ((char_length(TRIM(BOTH FROM scopes)) > 0))
);


ALTER TABLE auth.oauth_consents OWNER TO supabase_auth_admin;

--
-- Name: one_time_tokens; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.one_time_tokens (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    token_type auth.one_time_token_type NOT NULL,
    token_hash text NOT NULL,
    relates_to text NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    CONSTRAINT one_time_tokens_token_hash_check CHECK ((char_length(token_hash) > 0))
);


ALTER TABLE auth.one_time_tokens OWNER TO supabase_auth_admin;

--
-- Name: refresh_tokens; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.refresh_tokens (
    instance_id uuid,
    id bigint NOT NULL,
    token character varying(255),
    user_id character varying(255),
    revoked boolean,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    parent character varying(255),
    session_id uuid
);


ALTER TABLE auth.refresh_tokens OWNER TO supabase_auth_admin;

--
-- Name: TABLE refresh_tokens; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.refresh_tokens IS 'Auth: Store of tokens used to refresh JWT tokens once they expire.';


--
-- Name: refresh_tokens_id_seq; Type: SEQUENCE; Schema: auth; Owner: supabase_auth_admin
--

CREATE SEQUENCE auth.refresh_tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE auth.refresh_tokens_id_seq OWNER TO supabase_auth_admin;

--
-- Name: refresh_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: auth; Owner: supabase_auth_admin
--

ALTER SEQUENCE auth.refresh_tokens_id_seq OWNED BY auth.refresh_tokens.id;


--
-- Name: saml_providers; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.saml_providers (
    id uuid NOT NULL,
    sso_provider_id uuid NOT NULL,
    entity_id text NOT NULL,
    metadata_xml text NOT NULL,
    metadata_url text,
    attribute_mapping jsonb,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    name_id_format text,
    CONSTRAINT "entity_id not empty" CHECK ((char_length(entity_id) > 0)),
    CONSTRAINT "metadata_url not empty" CHECK (((metadata_url = NULL::text) OR (char_length(metadata_url) > 0))),
    CONSTRAINT "metadata_xml not empty" CHECK ((char_length(metadata_xml) > 0))
);


ALTER TABLE auth.saml_providers OWNER TO supabase_auth_admin;

--
-- Name: TABLE saml_providers; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.saml_providers IS 'Auth: Manages SAML Identity Provider connections.';


--
-- Name: saml_relay_states; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.saml_relay_states (
    id uuid NOT NULL,
    sso_provider_id uuid NOT NULL,
    request_id text NOT NULL,
    for_email text,
    redirect_to text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    flow_state_id uuid,
    CONSTRAINT "request_id not empty" CHECK ((char_length(request_id) > 0))
);


ALTER TABLE auth.saml_relay_states OWNER TO supabase_auth_admin;

--
-- Name: TABLE saml_relay_states; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.saml_relay_states IS 'Auth: Contains SAML Relay State information for each Service Provider initiated login.';


--
-- Name: schema_migrations; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.schema_migrations (
    version character varying(255) NOT NULL
);


ALTER TABLE auth.schema_migrations OWNER TO supabase_auth_admin;

--
-- Name: TABLE schema_migrations; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.schema_migrations IS 'Auth: Manages updates to the auth system.';


--
-- Name: sessions; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.sessions (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    factor_id uuid,
    aal auth.aal_level,
    not_after timestamp with time zone,
    refreshed_at timestamp without time zone,
    user_agent text,
    ip inet,
    tag text,
    oauth_client_id uuid,
    refresh_token_hmac_key text,
    refresh_token_counter bigint,
    scopes text,
    CONSTRAINT sessions_scopes_length CHECK ((char_length(scopes) <= 4096))
);


ALTER TABLE auth.sessions OWNER TO supabase_auth_admin;

--
-- Name: TABLE sessions; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.sessions IS 'Auth: Stores session data associated to a user.';


--
-- Name: COLUMN sessions.not_after; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON COLUMN auth.sessions.not_after IS 'Auth: Not after is a nullable column that contains a timestamp after which the session should be regarded as expired.';


--
-- Name: COLUMN sessions.refresh_token_hmac_key; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON COLUMN auth.sessions.refresh_token_hmac_key IS 'Holds a HMAC-SHA256 key used to sign refresh tokens for this session.';


--
-- Name: COLUMN sessions.refresh_token_counter; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON COLUMN auth.sessions.refresh_token_counter IS 'Holds the ID (counter) of the last issued refresh token.';


--
-- Name: sso_domains; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.sso_domains (
    id uuid NOT NULL,
    sso_provider_id uuid NOT NULL,
    domain text NOT NULL,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    CONSTRAINT "domain not empty" CHECK ((char_length(domain) > 0))
);


ALTER TABLE auth.sso_domains OWNER TO supabase_auth_admin;

--
-- Name: TABLE sso_domains; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.sso_domains IS 'Auth: Manages SSO email address domain mapping to an SSO Identity Provider.';


--
-- Name: sso_providers; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.sso_providers (
    id uuid NOT NULL,
    resource_id text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    disabled boolean,
    CONSTRAINT "resource_id not empty" CHECK (((resource_id = NULL::text) OR (char_length(resource_id) > 0)))
);


ALTER TABLE auth.sso_providers OWNER TO supabase_auth_admin;

--
-- Name: TABLE sso_providers; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.sso_providers IS 'Auth: Manages SSO identity provider information; see saml_providers for SAML.';


--
-- Name: COLUMN sso_providers.resource_id; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON COLUMN auth.sso_providers.resource_id IS 'Auth: Uniquely identifies a SSO provider according to a user-chosen resource ID (case insensitive), useful in infrastructure as code.';


--
-- Name: users; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.users (
    instance_id uuid,
    id uuid NOT NULL,
    aud character varying(255),
    role character varying(255),
    email character varying(255),
    encrypted_password character varying(255),
    email_confirmed_at timestamp with time zone,
    invited_at timestamp with time zone,
    confirmation_token character varying(255),
    confirmation_sent_at timestamp with time zone,
    recovery_token character varying(255),
    recovery_sent_at timestamp with time zone,
    email_change_token_new character varying(255),
    email_change character varying(255),
    email_change_sent_at timestamp with time zone,
    last_sign_in_at timestamp with time zone,
    raw_app_meta_data jsonb,
    raw_user_meta_data jsonb,
    is_super_admin boolean,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    phone text DEFAULT NULL::character varying,
    phone_confirmed_at timestamp with time zone,
    phone_change text DEFAULT ''::character varying,
    phone_change_token character varying(255) DEFAULT ''::character varying,
    phone_change_sent_at timestamp with time zone,
    confirmed_at timestamp with time zone GENERATED ALWAYS AS (LEAST(email_confirmed_at, phone_confirmed_at)) STORED,
    email_change_token_current character varying(255) DEFAULT ''::character varying,
    email_change_confirm_status smallint DEFAULT 0,
    banned_until timestamp with time zone,
    reauthentication_token character varying(255) DEFAULT ''::character varying,
    reauthentication_sent_at timestamp with time zone,
    is_sso_user boolean DEFAULT false NOT NULL,
    deleted_at timestamp with time zone,
    is_anonymous boolean DEFAULT false NOT NULL,
    CONSTRAINT users_email_change_confirm_status_check CHECK (((email_change_confirm_status >= 0) AND (email_change_confirm_status <= 2)))
);


ALTER TABLE auth.users OWNER TO supabase_auth_admin;

--
-- Name: TABLE users; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.users IS 'Auth: Stores user login data within a secure schema.';


--
-- Name: COLUMN users.is_sso_user; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON COLUMN auth.users.is_sso_user IS 'Auth: Set this column to true when the account comes from SSO. These accounts can have duplicate emails.';


--
-- Name: campaign_activities; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.campaign_activities (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    campaign_id uuid NOT NULL,
    contact_id uuid,
    organization_id text NOT NULL,
    user_id text,
    activity_type text NOT NULL,
    activity_data jsonb DEFAULT '{}'::jsonb NOT NULL,
    occurred_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.campaign_activities OWNER TO postgres;

--
-- Name: campaign_companies; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.campaign_companies (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    campaign_id uuid NOT NULL,
    company_id uuid NOT NULL,
    organization_id text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    blocked_by_icp boolean DEFAULT false,
    icp_profile_id_used uuid,
    icp_blocked_at timestamp with time zone,
    icp_failed_filters jsonb DEFAULT '[]'::jsonb,
    icp_score_when_blocked numeric(5,2)
);


ALTER TABLE public.campaign_companies OWNER TO postgres;

--
-- Name: COLUMN campaign_companies.blocked_by_icp; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.campaign_companies.blocked_by_icp IS 'Whether this company was blocked by ICP hard filters';


--
-- Name: COLUMN campaign_companies.icp_profile_id_used; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.campaign_companies.icp_profile_id_used IS 'The ICP profile ID that was used when this company was scored/blocked';


--
-- Name: COLUMN campaign_companies.icp_blocked_at; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.campaign_companies.icp_blocked_at IS 'Timestamp when company was blocked by ICP filters';


--
-- Name: COLUMN campaign_companies.icp_failed_filters; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.campaign_companies.icp_failed_filters IS 'Array of failed hard filter reasons when blocked';


--
-- Name: COLUMN campaign_companies.icp_score_when_blocked; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.campaign_companies.icp_score_when_blocked IS 'ICP score at time of blocking (usually 0 for hard filter failures)';


--
-- Name: campaign_emails; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.campaign_emails (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    campaign_id uuid NOT NULL,
    contact_id uuid NOT NULL,
    organization_id text NOT NULL,
    subject text,
    content text,
    status public.email_status DEFAULT 'draft'::public.email_status NOT NULL,
    message_id text,
    thread_id text,
    sent_at timestamp with time zone,
    delivered_at timestamp with time zone,
    opened_at timestamp with time zone,
    first_opened_at timestamp with time zone,
    clicked_at timestamp with time zone,
    replied_at timestamp with time zone,
    bounced_at timestamp with time zone,
    reply_content text,
    reply_received_at timestamp with time zone,
    open_count integer DEFAULT 0 NOT NULL,
    click_count integer DEFAULT 0 NOT NULL,
    error_message text,
    error_code text,
    approved_at timestamp with time zone,
    approved_by_user_id text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT campaign_emails_click_count_check CHECK ((click_count >= 0)),
    CONSTRAINT campaign_emails_open_count_check CHECK ((open_count >= 0))
);


ALTER TABLE public.campaign_emails OWNER TO postgres;

--
-- Name: campaign_files; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.campaign_files (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    campaign_id uuid NOT NULL,
    file_id uuid,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    file_name text,
    file_type text,
    file_url text,
    file_size integer,
    file_category text,
    uploaded_by text,
    uploaded_at timestamp with time zone DEFAULT now(),
    CONSTRAINT campaign_files_file_or_metadata_check CHECK (((file_id IS NOT NULL) OR ((file_name IS NOT NULL) AND (file_type IS NOT NULL) AND (file_url IS NOT NULL) AND (file_size IS NOT NULL))))
);


ALTER TABLE public.campaign_files OWNER TO postgres;

--
-- Name: TABLE campaign_files; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.campaign_files IS 'Stores campaign-specific files. Can either reference organization_files (general knowledge base) via file_id, or store campaign-specific files directly with metadata. Campaign-specific files are NOT included in the general knowledge base.';


--
-- Name: COLUMN campaign_files.campaign_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.campaign_files.campaign_id IS 'Reference to the campaign that uses this document';


--
-- Name: COLUMN campaign_files.file_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.campaign_files.file_id IS 'Reference to organization_file (if file is from general knowledge base). NULL for campaign-specific files.';


--
-- Name: campaign_seed_companies; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.campaign_seed_companies (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    campaign_id uuid NOT NULL,
    organization_id text NOT NULL,
    seed_company_url text NOT NULL,
    seed_company_name text,
    seed_company_id text,
    current_page integer DEFAULT 0 NOT NULL,
    total_pages_found integer,
    total_elements_found integer,
    is_active boolean DEFAULT false NOT NULL,
    is_completed boolean DEFAULT false NOT NULL,
    processing_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.campaign_seed_companies OWNER TO postgres;

--
-- Name: TABLE campaign_seed_companies; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.campaign_seed_companies IS 'Tracks seed companies used for lookalike discovery and their pagination state';


--
-- Name: COLUMN campaign_seed_companies.seed_company_url; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.campaign_seed_companies.seed_company_url IS 'LinkedIn URL of the seed company used for lookalike discovery';


--
-- Name: COLUMN campaign_seed_companies.current_page; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.campaign_seed_companies.current_page IS 'Current page number being processed (0-indexed)';


--
-- Name: COLUMN campaign_seed_companies.total_pages_found; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.campaign_seed_companies.total_pages_found IS 'Total number of pages available for this seed company';


--
-- Name: COLUMN campaign_seed_companies.total_elements_found; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.campaign_seed_companies.total_elements_found IS 'Total number of companies found for this seed company';


--
-- Name: COLUMN campaign_seed_companies.is_active; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.campaign_seed_companies.is_active IS 'Indicates which seed company is currently being processed';


--
-- Name: COLUMN campaign_seed_companies.is_completed; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.campaign_seed_companies.is_completed IS 'Indicates whether all pages have been processed for this seed company';


--
-- Name: COLUMN campaign_seed_companies.processing_order; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.campaign_seed_companies.processing_order IS 'Order in which seed companies should be processed (0 = first, 1 = second, etc.)';


--
-- Name: campaigns; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.campaigns (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id text NOT NULL,
    user_id text NOT NULL,
    name text NOT NULL,
    description text,
    campaign_type text DEFAULT 'email'::text NOT NULL,
    status public.campaign_status DEFAULT 'draft'::public.campaign_status NOT NULL,
    tags text[] DEFAULT '{}'::text[] NOT NULL,
    icp_min_employees integer,
    icp_max_employees integer,
    icp_sales_process text[] DEFAULT '{}'::text[] NOT NULL,
    icp_industries text[] DEFAULT '{}'::text[] NOT NULL,
    icp_job_titles text[] DEFAULT '{}'::text[] NOT NULL,
    icp_primary_regions text[] DEFAULT '{}'::text[] NOT NULL,
    icp_secondary_regions text[] DEFAULT '{}'::text[] NOT NULL,
    icp_focus_areas text[] DEFAULT '{}'::text[] NOT NULL,
    icp_pain_points text[] DEFAULT '{}'::text[] NOT NULL,
    icp_keywords text[] DEFAULT '{}'::text[] NOT NULL,
    target_audience jsonb DEFAULT '{}'::jsonb NOT NULL,
    settings jsonb DEFAULT '{}'::jsonb NOT NULL,
    product_description text,
    lead_source text,
    b2b_results jsonb,
    csv_results jsonb,
    curated_companies jsonb,
    selected_company_ids text[] DEFAULT '{}'::text[] NOT NULL,
    total_companies integer DEFAULT 0 NOT NULL,
    estimated_total_companies integer,
    b2b_search_filters jsonb DEFAULT '{}'::jsonb NOT NULL,
    b2b_search_page_size integer,
    b2b_search_last_page integer,
    b2b_search_total_pages integer,
    b2b_search_total_elements integer,
    csv_processed_index text[] DEFAULT '{}'::text[] NOT NULL,
    wizard_completed boolean DEFAULT false NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    started_at timestamp with time zone,
    launched_at timestamp with time zone,
    completed_at timestamp with time zone,
    language text DEFAULT 'en'::text NOT NULL,
    deep_research_provider text,
    deep_research_types text[] DEFAULT '{}'::text[],
    deep_research_override boolean DEFAULT false,
    icp_profile_id uuid,
    workflow jsonb,
    current_workflow_node_id uuid,
    csv_template_upload boolean DEFAULT false NOT NULL,
    lookalike_total_found integer DEFAULT 0,
    lookalike_total_processed integer DEFAULT 0,
    lookalike_last_page integer DEFAULT 0,
    lookalike_total_pages integer,
    autopilot_enabled boolean DEFAULT true NOT NULL,
    autopilot_company_verification boolean DEFAULT true NOT NULL,
    autopilot_email_review boolean DEFAULT true NOT NULL,
    autopilot_min_icp_score integer DEFAULT 70,
    autopilot_auto_decline_below_min_icp_score boolean DEFAULT true NOT NULL,
    autopilot_auto_confirm_initial_emails boolean DEFAULT true NOT NULL,
    autopilot_auto_confirm_followup_emails boolean DEFAULT true NOT NULL,
    autopilot_auto_confirm_reply_emails boolean DEFAULT false NOT NULL,
    CONSTRAINT autopilot_min_icp_score_range CHECK (((autopilot_min_icp_score IS NULL) OR ((autopilot_min_icp_score >= 0) AND (autopilot_min_icp_score <= 100)))),
    CONSTRAINT campaigns_check CHECK (((icp_min_employees IS NULL) OR (icp_max_employees IS NULL) OR (icp_min_employees <= icp_max_employees))),
    CONSTRAINT campaigns_icp_max_employees_check CHECK (((icp_max_employees IS NULL) OR (icp_max_employees >= 0))),
    CONSTRAINT campaigns_icp_min_employees_check CHECK (((icp_min_employees IS NULL) OR (icp_min_employees >= 0))),
    CONSTRAINT campaigns_total_companies_check CHECK ((total_companies >= 0))
);


ALTER TABLE public.campaigns OWNER TO postgres;

--
-- Name: COLUMN campaigns.language; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.campaigns.language IS 'Language code for campaign (en, en-gb, de, fr, sv). Default is en (English).';


--
-- Name: COLUMN campaigns.deep_research_provider; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.campaigns.deep_research_provider IS 'Deep research provider for this campaign: none, exa, perplexity, or both. If null, uses organization default.';


--
-- Name: COLUMN campaigns.deep_research_types; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.campaigns.deep_research_types IS 'Array of research types to enable: company_overview, funding_history, recent_news, competitive_landscape, growth_signals, icp_analysis. If empty, uses organization default.';


--
-- Name: COLUMN campaigns.deep_research_override; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.campaigns.deep_research_override IS 'If true, campaign uses its own deep research settings. If false or null, campaign inherits organization-level settings.';


--
-- Name: COLUMN campaigns.icp_profile_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.campaigns.icp_profile_id IS 'Link to ICP profile used for this campaign';


--
-- Name: COLUMN campaigns.workflow; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.campaigns.workflow IS 'JSON structure containing the workflow steps (Email → Wait pattern) with UUIDs for each node';


--
-- Name: COLUMN campaigns.current_workflow_node_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.campaigns.current_workflow_node_id IS 'UUID of the current workflow node being executed for this campaign';


--
-- Name: COLUMN campaigns.csv_template_upload; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.campaigns.csv_template_upload IS 'Indicates whether the campaign uses template CSV format (with First Name, Last Name, etc.) vs regular company-only CSV format';


--
-- Name: COLUMN campaigns.lookalike_total_found; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.campaigns.lookalike_total_found IS 'Total number of lookalike companies found based on selected seed companies';


--
-- Name: COLUMN campaigns.lookalike_total_processed; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.campaigns.lookalike_total_processed IS 'Total number of lookalike companies that have been processed';


--
-- Name: COLUMN campaigns.lookalike_last_page; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.campaigns.lookalike_last_page IS 'Last page number of lookalike companies fetched from B2B API';


--
-- Name: COLUMN campaigns.lookalike_total_pages; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.campaigns.lookalike_total_pages IS 'Total number of pages of lookalike companies available from B2B API';


--
-- Name: COLUMN campaigns.autopilot_enabled; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.campaigns.autopilot_enabled IS 'Master switch for autopilot mode - must be true for any auto-approval to work. Default: FALSE';


--
-- Name: COLUMN campaigns.autopilot_company_verification; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.campaigns.autopilot_company_verification IS 'When true, company verification tasks are automatically approved. Default: TRUE';


--
-- Name: COLUMN campaigns.autopilot_email_review; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.campaigns.autopilot_email_review IS 'When true, email review tasks are automatically accepted and sent. Default: TRUE';


--
-- Name: COLUMN campaigns.autopilot_min_icp_score; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.campaigns.autopilot_min_icp_score IS 'Minimum ICP score required for auto-approval (0-100). Companies below this score are auto-declined. Default: 70';


--
-- Name: COLUMN campaigns.autopilot_auto_decline_below_min_icp_score; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.campaigns.autopilot_auto_decline_below_min_icp_score IS 'When autopilot + company verification are enabled and a min ICP score is set: if TRUE, companies below min are auto-declined; if FALSE, they remain pending for manual review. Default: TRUE';


--
-- Name: COLUMN campaigns.autopilot_auto_confirm_initial_emails; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.campaigns.autopilot_auto_confirm_initial_emails IS 'When true (and autopilot enabled), initial/first outbound email tasks can be auto-accepted/sent. Default: TRUE.';


--
-- Name: COLUMN campaigns.autopilot_auto_confirm_followup_emails; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.campaigns.autopilot_auto_confirm_followup_emails IS 'When true (and autopilot enabled), follow-up outbound email tasks can be auto-accepted/sent. Default: TRUE.';


--
-- Name: COLUMN campaigns.autopilot_auto_confirm_reply_emails; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.campaigns.autopilot_auto_confirm_reply_emails IS 'When true (and autopilot enabled), reply email tasks can be auto-accepted/sent. Default: FALSE.';


--
-- Name: companies; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.companies (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id text NOT NULL,
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
    employee_count integer,
    founded_year integer,
    followers integer,
    location text,
    locations jsonb DEFAULT '{}'::jsonb NOT NULL,
    industries text[],
    specialities text[] DEFAULT '{}'::text[] NOT NULL,
    hashtags text[] DEFAULT '{}'::text[] NOT NULL,
    object_urn bigint,
    entity_urn text,
    used_for_outreach boolean DEFAULT false NOT NULL,
    phone text,
    icp_score jsonb,
    outreach_strategy jsonb,
    deep_research jsonb,
    useful_case_file_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    funding_data jsonb DEFAULT '{}'::jsonb NOT NULL,
    b2b_result jsonb,
    processing_status text DEFAULT 'pending'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    blocked_by_icp boolean DEFAULT false,
    sales_brief jsonb,
    processing_log jsonb,
    deep_research_v2 jsonb,
    failure_reason text,
    contact_extraction_status text DEFAULT 'extraction_not_started'::text,
    CONSTRAINT companies_employee_count_check CHECK (((employee_count IS NULL) OR (employee_count >= 0))),
    CONSTRAINT companies_followers_check CHECK (((followers IS NULL) OR (followers >= 0))),
    CONSTRAINT companies_founded_year_check CHECK (((founded_year IS NULL) OR ((founded_year >= 1800) AND ((founded_year)::numeric <= EXTRACT(year FROM CURRENT_DATE))))),
    CONSTRAINT companies_processing_status_check CHECK ((processing_status = ANY (ARRAY['pending'::text, 'scheduled'::text, 'processing'::text, 'processed'::text, 'approved'::text, 'declined'::text, 'failed'::text, 'blocked_by_icp'::text])))
);


ALTER TABLE public.companies OWNER TO postgres;

--
-- Name: TABLE companies; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.companies IS 'Updated: Removed has_linkedin_activity signal (not tracking yet)';


--
-- Name: COLUMN companies.processing_status; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.companies.processing_status IS 'Status of company data processing. Flow: scheduled → processing → processed → (approved OR declined OR blocked_by_icp). Valid values: pending, scheduled, processing, processed, approved, declined, failed, blocked_by_icp';


--
-- Name: COLUMN companies.blocked_by_icp; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.companies.blocked_by_icp IS 'Whether this company was blocked by ICP hard filters and should not be processed further';


--
-- Name: COLUMN companies.sales_brief; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.companies.sales_brief IS 'Sales brief information stored as markdown text. Contains key information about the company for sales purposes. Users can edit this directly.';


--
-- Name: COLUMN companies.processing_log; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.companies.processing_log IS 'Detailed log of company processing including B2B enrichment, deep research, ICP scoring, blocking decisions, and LLM outputs. Stored as JSONB for queryability.';


--
-- Name: COLUMN companies.deep_research_v2; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.companies.deep_research_v2 IS 'Comprehensive deep research results from Perplexity sonar-deep-research model. Contains full research report with citations, search results, and comprehensive analysis of the company including all available details from website, LinkedIn, industry information, etc.';


--
-- Name: COLUMN companies.failure_reason; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.companies.failure_reason IS 'Stores the reason why a company failed processing. Set when processing_status is changed to failed. Examples: campaign_link_creation_failed, icp_check_failed, enrichment_failed';


--
-- Name: COLUMN companies.contact_extraction_status; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.companies.contact_extraction_status IS 'Status of contact extraction: extraction_not_started, extracting_contacts, extraction_complete';


--
-- Name: company_activities; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.company_activities (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id text NOT NULL,
    company_id uuid NOT NULL,
    contact_id uuid,
    campaign_id uuid,
    task_id uuid,
    activity_type public.company_activity_type NOT NULL,
    title text NOT NULL,
    description text,
    created_by_user_id text NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.company_activities OWNER TO postgres;

--
-- Name: company_contacts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.company_contacts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    contact_id uuid NOT NULL,
    organization_id text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.company_contacts OWNER TO postgres;

--
-- Name: company_research_jobs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.company_research_jobs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    organization_id text NOT NULL,
    research_type text DEFAULT 'deep_research_v2'::text NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    research_types text[],
    campaign_id uuid,
    research_result jsonb,
    steps jsonb DEFAULT '[]'::jsonb,
    reasoning jsonb DEFAULT '{}'::jsonb,
    logs jsonb DEFAULT '[]'::jsonb,
    error_message text,
    error_details jsonb,
    created_at timestamp with time zone DEFAULT now(),
    started_at timestamp with time zone,
    completed_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT company_research_jobs_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'processing'::text, 'completed'::text, 'failed'::text])))
);


ALTER TABLE public.company_research_jobs OWNER TO postgres;

--
-- Name: TABLE company_research_jobs; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.company_research_jobs IS 'Stores async research jobs with detailed steps, reasoning, and logs. Each job tracks the complete research process including all API calls, decisions, and intermediate results.';


--
-- Name: COLUMN company_research_jobs.research_type; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.company_research_jobs.research_type IS 'Type of research: deep_research_v1 or deep_research_v2';


--
-- Name: COLUMN company_research_jobs.status; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.company_research_jobs.status IS 'Job status: pending, processing, completed, or failed';


--
-- Name: COLUMN company_research_jobs.research_types; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.company_research_jobs.research_types IS 'Array of specific research types selected (e.g., company_overview, funding_history, recent_news)';


--
-- Name: COLUMN company_research_jobs.research_result; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.company_research_jobs.research_result IS 'Full research result matching the format of deep_research or deep_research_v2 columns in companies table';


--
-- Name: COLUMN company_research_jobs.steps; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.company_research_jobs.steps IS 'Array of step objects: [{step: string, status: string, timestamp: string, reasoning: string, logs: array, input_data: object, output_data: object}]';


--
-- Name: COLUMN company_research_jobs.reasoning; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.company_research_jobs.reasoning IS 'Overall reasoning and decision-making process for the research job';


--
-- Name: COLUMN company_research_jobs.logs; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.company_research_jobs.logs IS 'Array of log entries: [{timestamp: string, level: string, message: string, data: object}]';


--
-- Name: contact_activities; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.contact_activities (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    contact_id uuid NOT NULL,
    organization_id text NOT NULL,
    user_id text,
    activity_type public.activity_type NOT NULL,
    title text NOT NULL,
    description text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    related_to_id uuid,
    related_to_type text,
    occurred_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.contact_activities OWNER TO postgres;

--
-- Name: contact_channels; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.contact_channels (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    contact_id uuid NOT NULL,
    organization_id text NOT NULL,
    channel_type public.channel_type NOT NULL,
    channel_value text NOT NULL,
    is_primary boolean DEFAULT false NOT NULL,
    is_verified boolean DEFAULT false NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.contact_channels OWNER TO postgres;

--
-- Name: contact_notes; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.contact_notes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    contact_id uuid NOT NULL,
    organization_id text NOT NULL,
    user_id text,
    content text NOT NULL,
    note_type text DEFAULT 'general'::text NOT NULL,
    is_pinned boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.contact_notes OWNER TO postgres;

--
-- Name: contacts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.contacts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id text NOT NULL,
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
    open_to_work boolean DEFAULT false NOT NULL,
    influencer boolean DEFAULT false NOT NULL,
    premium boolean DEFAULT false NOT NULL,
    educations jsonb,
    certifications jsonb,
    languages jsonb,
    skills jsonb,
    organizations jsonb DEFAULT '{}'::jsonb NOT NULL,
    patents jsonb DEFAULT '{}'::jsonb NOT NULL,
    awards jsonb DEFAULT '{}'::jsonb NOT NULL,
    projects jsonb DEFAULT '{}'::jsonb NOT NULL,
    publications jsonb DEFAULT '{}'::jsonb NOT NULL,
    courses jsonb DEFAULT '{}'::jsonb NOT NULL,
    test_scores jsonb DEFAULT '{}'::jsonb NOT NULL,
    position_groups jsonb DEFAULT '{}'::jsonb NOT NULL,
    volunteer_experiences jsonb DEFAULT '{}'::jsonb NOT NULL,
    recommendations text[] DEFAULT '{}'::text[] NOT NULL,
    network_info jsonb DEFAULT '{}'::jsonb NOT NULL,
    analysis jsonb,
    activities jsonb,
    email_validation_response jsonb,
    processing_status text DEFAULT 'pending'::text NOT NULL,
    pipeline_stage text,
    stage_updated_at timestamp with time zone,
    last_email_sentiment text,
    last_email_intent jsonb,
    last_thread_id text,
    last_incoming_email_at timestamp with time zone,
    ooo_until timestamp with time zone,
    unsubscribed_at timestamp with time zone,
    stop_drafts boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    phone text,
    b2b_email_requested boolean DEFAULT false,
    hunter_email_requested boolean DEFAULT false NOT NULL,
    hunter_email_response jsonb,
    provider_responses jsonb,
    icypeas_email_requested boolean DEFAULT false NOT NULL,
    icypeas_email_response jsonb,
    email_search_status text DEFAULT 'search_not_started'::text,
    do_not_contact boolean DEFAULT false NOT NULL,
    sales_brief jsonb,
    CONSTRAINT contacts_email_search_status_check CHECK ((email_search_status = ANY (ARRAY['search_not_started'::text, 'started_searching_email'::text, 'finished_searching_email'::text]))),
    CONSTRAINT contacts_last_email_sentiment_check CHECK (((last_email_sentiment IS NULL) OR (last_email_sentiment = ANY (ARRAY['VERY_POSITIVE'::text, 'POSITIVE'::text, 'NEUTRAL'::text, 'NEGATIVE'::text, 'VERY_NEGATIVE'::text])))),
    CONSTRAINT contacts_pipeline_stage_check CHECK (((pipeline_stage IS NULL) OR (pipeline_stage = ANY (ARRAY['PROSPECT'::text, 'LEAD'::text, 'APPOINTMENT_REQUESTED'::text, 'APPOINTMENT_SCHEDULED'::text, 'APPOINTMENT_CANCELLED'::text, 'PRESENTATION_SCHEDULED'::text, 'CONTRACT_NEGOTIATIONS'::text, 'AGREEMENT_IN_PRINCIPLE'::text, 'CLOSED_WON'::text, 'CLOSED_LOST'::text, 'REENGAGEMENT'::text])))),
    CONSTRAINT contacts_processing_status_check CHECK ((processing_status = ANY (ARRAY['pending'::text, 'processing'::text, 'completed'::text, 'failed'::text])))
);


ALTER TABLE public.contacts OWNER TO postgres;

--
-- Name: COLUMN contacts.processing_status; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.contacts.processing_status IS 'Status of contact data processing. Values: pending, processing, completed, failed';


--
-- Name: COLUMN contacts.phone; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.contacts.phone IS 'Contact phone number';


--
-- Name: COLUMN contacts.b2b_email_requested; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.contacts.b2b_email_requested IS 'Flag indicating if email enrichment has been requested from B2B API for this contact. Set to true when request is sent to prevent duplicate requests.';


--
-- Name: COLUMN contacts.hunter_email_requested; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.contacts.hunter_email_requested IS 'Flag indicating if email enrichment has been requested from Hunter.io API for this contact. Set to true when request is sent to prevent duplicate requests. Used as fallback when B2B enrichment fails.';


--
-- Name: COLUMN contacts.hunter_email_response; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.contacts.hunter_email_response IS 'Hunter.io API response stored as JSONB. Contains email finding results including email address, score, verification status, and metadata.';


--
-- Name: COLUMN contacts.provider_responses; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.contacts.provider_responses IS 'JSONB storage for email enrichment provider responses. Contains responses from various email finding services (Hunter.io, etc.) for tracking and debugging purposes.';


--
-- Name: COLUMN contacts.icypeas_email_requested; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.contacts.icypeas_email_requested IS 'Flag indicating if email enrichment has been requested from Icypeas API for this contact. Set to true when request is sent to prevent duplicate requests. Used as fallback when B2B enrichment and Hunter.io fail.';


--
-- Name: COLUMN contacts.icypeas_email_response; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.contacts.icypeas_email_response IS 'Icypeas API response stored as JSONB. Contains email finding results including email address, certainty level, MX records, and metadata.';


--
-- Name: COLUMN contacts.email_search_status; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.contacts.email_search_status IS 'Status of email address search: search_not_started, started_searching_email, finished_searching_email';


--
-- Name: COLUMN contacts.do_not_contact; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.contacts.do_not_contact IS 'Flag to mark contacts that should not be contacted. When true, all email communication is blocked and tasks are deleted.';


--
-- Name: COLUMN contacts.sales_brief; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.contacts.sales_brief IS 'Sales brief information stored as markdown text. Contains key information about the contact for sales purposes. Users can edit this directly.';


--
-- Name: conversation_messages; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.conversation_messages (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    conversation_id uuid NOT NULL,
    organization_id text NOT NULL,
    sender_type text NOT NULL,
    sender_user_id text,
    content text NOT NULL,
    subject text,
    channel_type public.channel_type DEFAULT 'email'::public.channel_type NOT NULL,
    message_type text DEFAULT 'text'::text NOT NULL,
    email_message_id text,
    in_reply_to text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    sent_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT conversation_messages_sender_type_check CHECK ((sender_type = ANY (ARRAY['user'::text, 'contact'::text])))
);


ALTER TABLE public.conversation_messages OWNER TO postgres;

--
-- Name: conversations; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.conversations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    contact_id uuid NOT NULL,
    organization_id text NOT NULL,
    user_id text,
    subject text NOT NULL,
    channel_type public.channel_type DEFAULT 'email'::public.channel_type NOT NULL,
    status text DEFAULT 'open'::text NOT NULL,
    priority text DEFAULT 'normal'::text NOT NULL,
    account_email text,
    is_unread boolean DEFAULT true NOT NULL,
    tags text[] DEFAULT '{}'::text[] NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    last_message_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT conversations_priority_check CHECK ((priority = ANY (ARRAY['high'::text, 'normal'::text, 'low'::text]))),
    CONSTRAINT conversations_status_check CHECK ((status = ANY (ARRAY['open'::text, 'pending'::text, 'closed'::text])))
);


ALTER TABLE public.conversations OWNER TO postgres;

--
-- Name: deep_research_settings; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.deep_research_settings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id text NOT NULL,
    selected_providers text[] DEFAULT '{}'::text[] NOT NULL,
    selected_research_types text[] DEFAULT '{}'::text[] NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.deep_research_settings OWNER TO postgres;

--
-- Name: document_access_events; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.document_access_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    short_url_id uuid NOT NULL,
    short_code text NOT NULL,
    contact_id uuid,
    organization_id text NOT NULL,
    event_type text NOT NULL,
    file_id uuid NOT NULL,
    file_name text,
    accessed_at timestamp with time zone DEFAULT now(),
    ip_address text,
    user_agent text,
    referrer text,
    session_id text,
    duration_seconds integer,
    metadata jsonb DEFAULT '{}'::jsonb
);


ALTER TABLE public.document_access_events OWNER TO postgres;

--
-- Name: TABLE document_access_events; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.document_access_events IS 'Detailed tracking of every document access - who opened, when, for how long';


--
-- Name: COLUMN document_access_events.event_type; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.document_access_events.event_type IS 'Event type: "opened" (link clicked), "downloaded" (file downloaded), "viewed" (page viewed)';


--
-- Name: COLUMN document_access_events.session_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.document_access_events.session_id IS 'Browser session ID for tracking multiple events from same visit';


--
-- Name: COLUMN document_access_events.duration_seconds; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.document_access_events.duration_seconds IS 'How long the document was viewed (if tracked by frontend)';


--
-- Name: document_short_urls; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.document_short_urls (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    short_code text NOT NULL,
    organization_id text NOT NULL,
    file_id uuid NOT NULL,
    file_name text NOT NULL,
    file_category text,
    contact_id uuid,
    campaign_id uuid,
    shared_via text,
    expires_at timestamp with time zone NOT NULL,
    access_count integer DEFAULT 0,
    last_accessed_at timestamp with time zone,
    first_accessed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    created_by text
);


ALTER TABLE public.document_short_urls OWNER TO postgres;

--
-- Name: TABLE document_short_urls; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.document_short_urls IS 'Short URL mappings for document sharing (like bit.ly) - replaces long JWT tokens with short codes';


--
-- Name: COLUMN document_short_urls.short_code; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.document_short_urls.short_code IS 'Short alphanumeric code (e.g., "xK9mP2") - 6 characters, URL-safe';


--
-- Name: COLUMN document_short_urls.contact_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.document_short_urls.contact_id IS 'Contact this document was shared with (for tracking)';


--
-- Name: COLUMN document_short_urls.shared_via; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.document_short_urls.shared_via IS 'How it was shared: "email", "manual_share", "link_copy"';


--
-- Name: COLUMN document_short_urls.expires_at; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.document_short_urls.expires_at IS 'Expiration timestamp - default 30 days, extended to 90 days for case studies';


--
-- Name: COLUMN document_short_urls.access_count; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.document_short_urls.access_count IS 'Total number of times this short URL was accessed';


--
-- Name: feedback; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.feedback (
    id integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    organization_id text NOT NULL,
    interview_id text,
    email text,
    feedback text,
    satisfaction integer,
    CONSTRAINT feedback_satisfaction_check CHECK (((satisfaction IS NULL) OR ((satisfaction >= 1) AND (satisfaction <= 5))))
);


ALTER TABLE public.feedback OWNER TO postgres;

--
-- Name: feedback_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.feedback_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.feedback_id_seq OWNER TO postgres;

--
-- Name: feedback_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.feedback_id_seq OWNED BY public.feedback.id;


--
-- Name: icp_profiles; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.icp_profiles (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id text NOT NULL,
    name text NOT NULL,
    description text,
    is_default boolean DEFAULT false,
    criteria jsonb DEFAULT '{}'::jsonb,
    boosts_penalties jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT icp_profiles_name_check CHECK (((char_length(name) >= 1) AND (char_length(name) <= 255)))
);


ALTER TABLE public.icp_profiles OWNER TO postgres;

--
-- Name: TABLE icp_profiles; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.icp_profiles IS 'Ideal Customer Profile configurations with weighted scoring criteria. Each organization should have at least one default profile.';


--
-- Name: COLUMN icp_profiles.id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.icp_profiles.id IS 'Unique identifier for the ICP profile';


--
-- Name: COLUMN icp_profiles.organization_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.icp_profiles.organization_id IS 'Organization that owns this profile';


--
-- Name: COLUMN icp_profiles.name; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.icp_profiles.name IS 'Profile name (1-255 characters, unique per organization)';


--
-- Name: COLUMN icp_profiles.description; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.icp_profiles.description IS 'Optional description of the profile';


--
-- Name: COLUMN icp_profiles.is_default; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.icp_profiles.is_default IS 'Whether this is the default profile for the organization';


--
-- Name: COLUMN icp_profiles.criteria; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.icp_profiles.criteria IS 'JSONB object containing criterion configurations (industries, company_size, regions, etc.)';


--
-- Name: COLUMN icp_profiles.boosts_penalties; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.icp_profiles.boosts_penalties IS 'Boosts and penalties for ICP scoring (deprecated - kept for backward compatibility but should be empty)';


--
-- Name: interview; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.interview (
    id text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    organization_id text NOT NULL,
    user_id text,
    interviewer_id integer,
    name text,
    description text,
    objective text,
    logo_url text,
    theme_color text,
    url text,
    readable_slug text,
    is_active boolean DEFAULT true NOT NULL,
    is_anonymous boolean DEFAULT false NOT NULL,
    is_archived boolean DEFAULT false NOT NULL,
    questions jsonb,
    quotes text[],
    insights text[],
    respondents text[],
    question_count integer,
    response_count integer,
    time_duration text
);


ALTER TABLE public.interview OWNER TO postgres;

--
-- Name: interviewer; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.interviewer (
    id integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    organization_id text NOT NULL,
    agent_id text,
    name text NOT NULL,
    description text NOT NULL,
    image text NOT NULL,
    audio text,
    empathy integer NOT NULL,
    exploration integer NOT NULL,
    rapport integer NOT NULL,
    speed integer NOT NULL,
    CONSTRAINT interviewer_empathy_check CHECK (((empathy >= 0) AND (empathy <= 100))),
    CONSTRAINT interviewer_exploration_check CHECK (((exploration >= 0) AND (exploration <= 100))),
    CONSTRAINT interviewer_rapport_check CHECK (((rapport >= 0) AND (rapport <= 100))),
    CONSTRAINT interviewer_speed_check CHECK (((speed >= 0) AND (speed <= 100)))
);


ALTER TABLE public.interviewer OWNER TO postgres;

--
-- Name: interviewer_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.interviewer_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.interviewer_id_seq OWNER TO postgres;

--
-- Name: interviewer_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.interviewer_id_seq OWNED BY public.interviewer.id;


--
-- Name: organization; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.organization (
    id text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    name text,
    image_url text,
    allowed_responses_count integer DEFAULT 0 NOT NULL,
    plan public.plan DEFAULT 'free'::public.plan,
    deleted boolean DEFAULT false NOT NULL,
    CONSTRAINT organization_allowed_responses_count_check CHECK ((allowed_responses_count >= 0))
);


ALTER TABLE public.organization OWNER TO postgres;

--
-- Name: COLUMN organization.deleted; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.organization.deleted IS 'Flag to mark organization as deleted (set to true when organization is deleted from Clerk, instead of hard deleting the record)';


--
-- Name: organization_files; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.organization_files (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id text NOT NULL,
    file_name text NOT NULL,
    file_type text NOT NULL,
    file_url text NOT NULL,
    file_size integer NOT NULL,
    file_category public.file_category_enum DEFAULT 'documents'::public.file_category_enum NOT NULL,
    full_text text,
    pages_count integer DEFAULT 0 NOT NULL,
    shared_with_client boolean DEFAULT false NOT NULL,
    uploaded_by text NOT NULL,
    uploaded_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    has_sensitive_data boolean DEFAULT false,
    sensitive_data_types text[] DEFAULT '{}'::text[],
    file_hash text,
    processing_status text DEFAULT 'pending'::text,
    industries text[] DEFAULT '{}'::text[],
    CONSTRAINT organization_files_file_size_check CHECK ((file_size >= 0)),
    CONSTRAINT organization_files_pages_count_check CHECK ((pages_count >= 0)),
    CONSTRAINT organization_files_processing_status_check CHECK ((processing_status = ANY (ARRAY['pending'::text, 'processing'::text, 'processed'::text, 'error'::text])))
);


ALTER TABLE public.organization_files OWNER TO postgres;

--
-- Name: COLUMN organization_files.file_category; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.organization_files.file_category IS 'Category of the file: documents, transcripts, internal_documents, sales_papers, sait_guidelines, brand_guidelines, case_study, sales_scripts, images, presentations, spreadsheets, proposals, other';


--
-- Name: COLUMN organization_files.has_sensitive_data; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.organization_files.has_sensitive_data IS 'Flag indicating if sensitive information (PII, financial data, etc.) was detected in this document during screening';


--
-- Name: COLUMN organization_files.sensitive_data_types; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.organization_files.sensitive_data_types IS 'Array of sensitive data types detected (e.g., email, phone, ssn, credit_card, api_key, etc.)';


--
-- Name: COLUMN organization_files.file_hash; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.organization_files.file_hash IS 'SHA-256 hash of the file content. Used to detect duplicate files within the same organization.';


--
-- Name: COLUMN organization_files.processing_status; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.organization_files.processing_status IS 'Status of document processing: pending (not started), processing (in progress), processed (completed), error (failed)';


--
-- Name: COLUMN organization_files.industries; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.organization_files.industries IS 'Array of industry codes that this case study is relevant for. Empty array means applicable to all industries. Only used for case_study file category.';


--
-- Name: organization_files_chunks; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.organization_files_chunks (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id text NOT NULL,
    file_id uuid NOT NULL,
    chunk_text text NOT NULL,
    embedding public.vector,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.organization_files_chunks OWNER TO postgres;

--
-- Name: organization_icp_linkedin_urls; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.organization_icp_linkedin_urls (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id text NOT NULL,
    url text NOT NULL,
    url_type text NOT NULL,
    added_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT organization_icp_linkedin_urls_url_type_check CHECK ((url_type = ANY (ARRAY['current_customer'::text, 'ideal_customer'::text, 'ideal_person'::text, 'exclusion'::text])))
);


ALTER TABLE public.organization_icp_linkedin_urls OWNER TO postgres;

--
-- Name: organization_settings; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.organization_settings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id text NOT NULL,
    general_settings jsonb DEFAULT '{}'::jsonb NOT NULL,
    notification_settings jsonb DEFAULT '{}'::jsonb NOT NULL,
    api_credentials jsonb DEFAULT '{"cal_com_api_key": "", "calendly_api_key": ""}'::jsonb NOT NULL,
    onboarding_completed boolean DEFAULT false NOT NULL,
    onboarding_completed_at timestamp with time zone,
    onboarding_skipped boolean DEFAULT false NOT NULL,
    onboarding_skipped_at timestamp with time zone,
    company_website text,
    company_linkedin_profile text,
    company_description text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    contact_extraction_limit integer DEFAULT 5 NOT NULL,
    default_campaign_language text DEFAULT 'en'::text,
    api_key text,
    api_key_created_at timestamp with time zone,
    api_key_info_shown boolean DEFAULT false NOT NULL,
    CONSTRAINT check_contact_extraction_limit_range CHECK (((contact_extraction_limit >= 1) AND (contact_extraction_limit <= 10)))
);


ALTER TABLE public.organization_settings OWNER TO postgres;

--
-- Name: COLUMN organization_settings.contact_extraction_limit; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.organization_settings.contact_extraction_limit IS 'Maximum number of contacts to extract per company (default: 5, range: 1-10)';


--
-- Name: COLUMN organization_settings.default_campaign_language; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.organization_settings.default_campaign_language IS 'Default language code for new campaigns (en, en-gb, de, fr, sv). Default is en (English).';


--
-- Name: COLUMN organization_settings.api_key; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.organization_settings.api_key IS 'Unique API key for organization to access external APIs. Generated securely and stored as plain text for authentication purposes.';


--
-- Name: COLUMN organization_settings.api_key_created_at; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.organization_settings.api_key_created_at IS 'Timestamp when the API key was first created or last regenerated.';


--
-- Name: COLUMN organization_settings.api_key_info_shown; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.organization_settings.api_key_info_shown IS 'Flag indicating if the user has been informed about the API key feature. Used to show informational notification only once.';


--
-- Name: response; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.response (
    id integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    organization_id text NOT NULL,
    interview_id text,
    name text,
    email text,
    call_id text,
    candidate_status text,
    duration integer,
    tab_switch_count integer DEFAULT 0 NOT NULL,
    details jsonb,
    analytics jsonb,
    is_analysed boolean DEFAULT false NOT NULL,
    is_ended boolean DEFAULT false NOT NULL,
    is_viewed boolean DEFAULT false NOT NULL,
    CONSTRAINT response_duration_check CHECK (((duration IS NULL) OR (duration >= 0))),
    CONSTRAINT response_tab_switch_count_check CHECK ((tab_switch_count >= 0))
);


ALTER TABLE public.response OWNER TO postgres;

--
-- Name: response_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.response_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.response_id_seq OWNER TO postgres;

--
-- Name: response_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.response_id_seq OWNED BY public.response.id;


--
-- Name: style_guidelines; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.style_guidelines (
    id integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    organization_id text NOT NULL,
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


ALTER TABLE public.style_guidelines OWNER TO postgres;

--
-- Name: style_guidelines_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.style_guidelines_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.style_guidelines_id_seq OWNER TO postgres;

--
-- Name: style_guidelines_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.style_guidelines_id_seq OWNED BY public.style_guidelines.id;


--
-- Name: system_config; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.system_config (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    key text NOT NULL,
    value jsonb NOT NULL,
    description text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.system_config OWNER TO postgres;

--
-- Name: tasks; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tasks (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id text NOT NULL,
    created_by_user_id text,
    completed_by_user_id text,
    title text NOT NULL,
    description text,
    task_type public.task_type,
    priority text,
    contact_id uuid,
    company_id uuid,
    campaign_id uuid,
    thread_id text,
    email_id text,
    pre_generated_copy text,
    reasoning_note text,
    due_date timestamp with time zone,
    completed_at timestamp with time zone,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    sent_at timestamp with time zone,
    scheduled boolean DEFAULT false NOT NULL,
    subject text,
    generation_log jsonb DEFAULT '{}'::jsonb,
    body text,
    priority_rank integer DEFAULT 3 NOT NULL,
    send_status text DEFAULT 'not_sent'::text,
    send_error_message text,
    conversation_summary jsonb DEFAULT '{}'::jsonb,
    conversation_summary_text text,
    feedback text,
    status public.task_status DEFAULT 'pending'::public.task_status NOT NULL,
    CONSTRAINT tasks_feedback_check CHECK (((feedback IS NULL) OR (feedback = ANY (ARRAY['liked'::text, 'disliked'::text])))),
    CONSTRAINT tasks_priority_check CHECK (((priority IS NULL) OR (priority = ANY (ARRAY['low'::text, 'normal'::text, 'high'::text, 'urgent'::text])))),
    CONSTRAINT tasks_send_status_check CHECK (((send_status IS NULL) OR (send_status = ANY (ARRAY['not_sent'::text, 'sending'::text, 'sent_success'::text, 'sent_failed'::text]))))
);


ALTER TABLE public.tasks OWNER TO postgres;

--
-- Name: COLUMN tasks.created_by_user_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.tasks.created_by_user_id IS 'User who created the task. NULL for automated/cron-generated tasks.';


--
-- Name: COLUMN tasks.title; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.tasks.title IS 'Display title for the task (e.g., "Review email draft for John Doe")';


--
-- Name: COLUMN tasks.pre_generated_copy; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.tasks.pre_generated_copy IS 'Original AI-generated email body. Kept as reference, never modified after initial generation.';


--
-- Name: COLUMN tasks.sent_at; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.tasks.sent_at IS 'Timestamp when email was sent (immediate) or will be sent (scheduled). Used for follow-up timing calculations.';


--
-- Name: COLUMN tasks.scheduled; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.tasks.scheduled IS 'Indicates whether the email was scheduled for future delivery (true) or sent immediately (false).';


--
-- Name: COLUMN tasks.subject; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.tasks.subject IS 'Actual email subject line to be sent. Used for email-related tasks.';


--
-- Name: COLUMN tasks.generation_log; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.tasks.generation_log IS 'Comprehensive logging of email generation process including all steps, inputs, outputs, models used, templates, context data, and any errors';


--
-- Name: COLUMN tasks.body; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.tasks.body IS 'User-editable email body. This is what gets sent to Gmail API. Initially copied from pre_generated_copy.';


--
-- Name: COLUMN tasks.priority_rank; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.tasks.priority_rank IS 'Numeric priority rank for database sorting: 1=urgent, 2=high, 3=normal, 4=low';


--
-- Name: COLUMN tasks.send_status; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.tasks.send_status IS 'Email send status: not_sent (default), sending, sent_success, sent_failed. Used by frontend to track email delivery state.';


--
-- Name: COLUMN tasks.send_error_message; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.tasks.send_error_message IS 'Error message if email send failed';


--
-- Name: COLUMN tasks.conversation_summary; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.tasks.conversation_summary IS 'Stores conversation context including:
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


--
-- Name: COLUMN tasks.conversation_summary_text; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.tasks.conversation_summary_text IS 'Human-readable conversation summary for frontend display. Example:
"Discussed Sellton product features and scheduling. User asked about team size, company history, and use cases. We answered all questions and provided meeting slots for Dec 22-24. Waiting for time confirmation."';


--
-- Name: COLUMN tasks.feedback; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.tasks.feedback IS 'User feedback on task quality for training purposes.
Values: null (no feedback), ''liked'' (good quality), ''disliked'' (poor quality).
Used to identify good/bad email copy and company verification quality.';


--
-- Name: template_csv_export; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.template_csv_export AS
 SELECT COALESCE(c.firstname, split_part(c.name, ' '::text, 1), ''::text) AS "First Name",
    COALESCE(c.lastname,
        CASE
            WHEN (split_part(c.name, ' '::text, 2) <> ''::text) THEN split_part(c.name, ' '::text, 2)
            ELSE ''::text
        END, ''::text) AS "Last Name",
    COALESCE(c.headline, ''::text) AS "Title",
    COALESCE(comp.name, ''::text) AS "Company Name",
    COALESCE(comp.website, ''::text) AS "Company website",
    COALESCE(c.linkedin_url, ''::text) AS "Personal LinkedIn",
    COALESCE(comp.linkedin_url, ''::text) AS "Company LinkedIn",
    COALESCE(
        CASE
            WHEN ((comp.website IS NOT NULL) AND (comp.website <> ''::text)) THEN ('info@'::text || regexp_replace(comp.website, '^https?://(www\.)?'::text, ''::text, 'gi'::text))
            ELSE ''::text
        END, ''::text) AS "Company email address",
    COALESCE(c.email, ''::text) AS "Personal Email address",
    COALESCE(c.phone, ''::text) AS "Mobile Number",
    COALESCE(comp.phone, ''::text) AS "Company Number",
    COALESCE(
        CASE
            WHEN ((c.location IS NOT NULL) AND (jsonb_typeof(c.location) = 'object'::text)) THEN
            CASE
                WHEN (((c.location ->> 'default'::text) IS NOT NULL) AND ((c.location ->> 'default'::text) <> ''::text)) THEN (c.location ->> 'default'::text)
                WHEN (((c.location ->> 'city'::text) IS NOT NULL) AND ((c.location ->> 'country'::text) IS NOT NULL)) THEN (((c.location ->> 'city'::text) || ', '::text) || (c.location ->> 'country'::text))
                WHEN (((c.location ->> 'city'::text) IS NOT NULL) AND ((c.location ->> 'city'::text) <> ''::text)) THEN (c.location ->> 'city'::text)
                WHEN (((c.location ->> 'country'::text) IS NOT NULL) AND ((c.location ->> 'country'::text) <> ''::text)) THEN (c.location ->> 'country'::text)
                ELSE ''::text
            END
            ELSE ''::text
        END, ''::text) AS "Person location",
    COALESCE(comp.location, ''::text) AS "Company location",
    COALESCE(c.pipeline_stage, 'PROSPECT'::text) AS "Stage",
    COALESCE(
        CASE
            WHEN ((c.skills IS NOT NULL) AND (jsonb_typeof(c.skills) = 'array'::text)) THEN array_to_string(ARRAY( SELECT jsonb_array_elements_text(c.skills) AS jsonb_array_elements_text), ', '::text)
            WHEN ((comp.specialities IS NOT NULL) AND (array_length(comp.specialities, 1) > 0)) THEN array_to_string(comp.specialities, ', '::text)
            ELSE ''::text
        END, ''::text) AS "Technologies used"
   FROM ((public.contacts c
     JOIN public.company_contacts cc ON (((cc.contact_id = c.id) AND (cc.organization_id = c.organization_id))))
     JOIN public.companies comp ON (((comp.id = cc.company_id) AND (comp.organization_id = c.organization_id))))
  WHERE (c.organization_id = 'YOUR_ORGANIZATION_ID'::text)
  ORDER BY comp.name, c.name;


ALTER VIEW public.template_csv_export OWNER TO postgres;

--
-- Name: token_usage; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.token_usage (
    id bigint NOT NULL,
    organization_id text NOT NULL,
    session_id text NOT NULL,
    provider text NOT NULL,
    model_name text,
    total_calls integer DEFAULT 0 NOT NULL,
    total_input_tokens integer DEFAULT 0 NOT NULL,
    total_output_tokens integer DEFAULT 0 NOT NULL,
    total_tokens integer DEFAULT 0 NOT NULL,
    total_audio_tokens integer DEFAULT 0 NOT NULL,
    total_cached_tokens integer DEFAULT 0 NOT NULL,
    total_reasoning_tokens integer DEFAULT 0 NOT NULL,
    total_prompt_tokens integer DEFAULT 0 NOT NULL,
    total_completion_tokens integer DEFAULT 0 NOT NULL,
    total_processing_time numeric DEFAULT 0 NOT NULL,
    tracking_start timestamp with time zone NOT NULL,
    tracking_end timestamp with time zone NOT NULL,
    run_id text,
    run_created_at timestamp with time zone,
    agent_id text,
    content text,
    content_type text,
    event text,
    metrics_raw jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT token_usage_check CHECK ((tracking_start <= tracking_end)),
    CONSTRAINT token_usage_total_audio_tokens_check CHECK ((total_audio_tokens >= 0)),
    CONSTRAINT token_usage_total_cached_tokens_check CHECK ((total_cached_tokens >= 0)),
    CONSTRAINT token_usage_total_calls_check CHECK ((total_calls >= 0)),
    CONSTRAINT token_usage_total_completion_tokens_check CHECK ((total_completion_tokens >= 0)),
    CONSTRAINT token_usage_total_input_tokens_check CHECK ((total_input_tokens >= 0)),
    CONSTRAINT token_usage_total_output_tokens_check CHECK ((total_output_tokens >= 0)),
    CONSTRAINT token_usage_total_processing_time_check CHECK ((total_processing_time >= (0)::numeric)),
    CONSTRAINT token_usage_total_prompt_tokens_check CHECK ((total_prompt_tokens >= 0)),
    CONSTRAINT token_usage_total_reasoning_tokens_check CHECK ((total_reasoning_tokens >= 0)),
    CONSTRAINT token_usage_total_tokens_check CHECK ((total_tokens >= 0))
);


ALTER TABLE public.token_usage OWNER TO postgres;

--
-- Name: token_usage_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.token_usage_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.token_usage_id_seq OWNER TO postgres;

--
-- Name: token_usage_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.token_usage_id_seq OWNED BY public.token_usage.id;


--
-- Name: usage; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.usage (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id text NOT NULL,
    session_id text NOT NULL,
    provider text NOT NULL,
    model_name text,
    api_calls integer DEFAULT 0 NOT NULL,
    input_tokens integer DEFAULT 0 NOT NULL,
    output_tokens integer DEFAULT 0 NOT NULL,
    total_tokens integer DEFAULT 0 NOT NULL,
    run_id text,
    agent_id text,
    description text,
    usage_context text DEFAULT 'direct_api'::text NOT NULL,
    tracking_start timestamp with time zone DEFAULT now() NOT NULL,
    tracking_end timestamp with time zone DEFAULT now() NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    campaign_id text,
    original_pricing jsonb DEFAULT '{}'::jsonb,
    sellton_pricing jsonb DEFAULT '{}'::jsonb,
    original_cost numeric(12,6) DEFAULT 0,
    sellton_cost numeric(12,6) DEFAULT 0,
    CONSTRAINT usage_api_calls_check CHECK ((api_calls >= 0)),
    CONSTRAINT usage_check CHECK ((tracking_start <= tracking_end)),
    CONSTRAINT usage_input_tokens_check CHECK ((input_tokens >= 0)),
    CONSTRAINT usage_output_tokens_check CHECK ((output_tokens >= 0)),
    CONSTRAINT usage_total_tokens_check CHECK ((total_tokens >= 0))
);


ALTER TABLE public.usage OWNER TO postgres;

--
-- Name: COLUMN usage.campaign_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.usage.campaign_id IS 'Campaign ID for tracking usage per campaign (nullable - not all usage is campaign-related)';


--
-- Name: COLUMN usage.original_pricing; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.usage.original_pricing IS 'Original provider pricing at time of usage (JSONB with model pricing info)';


--
-- Name: COLUMN usage.sellton_pricing; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.usage.sellton_pricing IS 'Sellton pricing applied at time of usage (JSONB with model pricing info)';


--
-- Name: COLUMN usage.original_cost; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.usage.original_cost IS 'Calculated cost using original provider pricing at time of usage';


--
-- Name: COLUMN usage.sellton_cost; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.usage.sellton_cost IS 'Calculated cost using Sellton pricing at time of usage';


--
-- Name: usage_cost_by_context; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.usage_cost_by_context AS
 SELECT organization_id,
    usage_context,
    sum(COALESCE(original_cost, (0)::numeric)) AS total_original_cost,
    sum(COALESCE(sellton_cost, (0)::numeric)) AS total_sellton_cost,
    sum(COALESCE(input_tokens, 0)) AS total_input_tokens,
    sum(COALESCE(output_tokens, 0)) AS total_output_tokens,
    sum(COALESCE(total_tokens, 0)) AS total_tokens,
    sum(COALESCE(api_calls, 0)) AS total_api_calls,
    count(DISTINCT provider) AS unique_providers,
    count(DISTINCT model_name) AS unique_models,
    count(DISTINCT campaign_id) AS unique_campaigns,
    count(DISTINCT session_id) AS unique_sessions,
    count(*) AS total_records,
    min(created_at) AS first_usage_at,
    max(created_at) AS last_usage_at
   FROM public.usage
  WHERE (usage_context IS NOT NULL)
  GROUP BY organization_id, usage_context;


ALTER VIEW public.usage_cost_by_context OWNER TO postgres;

--
-- Name: VIEW usage_cost_by_context; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON VIEW public.usage_cost_by_context IS 'Total aggregated usage costs and token spend per organization and usage context';


--
-- Name: usage_cost_daily; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.usage_cost_daily AS
 SELECT organization_id,
    date(created_at) AS usage_date,
    sum(COALESCE(original_cost, (0)::numeric)) AS total_original_cost,
    sum(COALESCE(sellton_cost, (0)::numeric)) AS total_sellton_cost,
    sum(COALESCE(input_tokens, 0)) AS total_input_tokens,
    sum(COALESCE(output_tokens, 0)) AS total_output_tokens,
    sum(COALESCE(total_tokens, 0)) AS total_tokens,
    sum(COALESCE(api_calls, 0)) AS total_api_calls,
    count(DISTINCT provider) AS unique_providers,
    count(DISTINCT model_name) AS unique_models,
    count(DISTINCT session_id) AS unique_sessions,
    count(DISTINCT campaign_id) AS unique_campaigns,
    count(*) AS total_records,
    min(created_at) AS first_usage_at,
    max(created_at) AS last_usage_at
   FROM public.usage
  WHERE ((created_at IS NOT NULL) AND (campaign_id IS NOT NULL))
  GROUP BY organization_id, (date(created_at));


ALTER VIEW public.usage_cost_daily OWNER TO postgres;

--
-- Name: VIEW usage_cost_daily; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON VIEW public.usage_cost_daily IS 'Daily aggregated usage costs and token spend per organization (excluding records without campaign_id)';


--
-- Name: usage_cost_daily_by_campaign; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.usage_cost_daily_by_campaign AS
 SELECT organization_id,
    campaign_id,
    date(created_at) AS usage_date,
    sum(COALESCE(original_cost, (0)::numeric)) AS total_original_cost,
    sum(COALESCE(sellton_cost, (0)::numeric)) AS total_sellton_cost,
    sum(COALESCE(input_tokens, 0)) AS total_input_tokens,
    sum(COALESCE(output_tokens, 0)) AS total_output_tokens,
    sum(COALESCE(total_tokens, 0)) AS total_tokens,
    sum(COALESCE(api_calls, 0)) AS total_api_calls,
    count(DISTINCT provider) AS unique_providers,
    count(DISTINCT model_name) AS unique_models,
    count(DISTINCT session_id) AS unique_sessions,
    count(*) AS total_records,
    min(created_at) AS first_usage_at,
    max(created_at) AS last_usage_at
   FROM public.usage
  WHERE ((created_at IS NOT NULL) AND (campaign_id IS NOT NULL))
  GROUP BY organization_id, campaign_id, (date(created_at));


ALTER VIEW public.usage_cost_daily_by_campaign OWNER TO postgres;

--
-- Name: VIEW usage_cost_daily_by_campaign; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON VIEW public.usage_cost_daily_by_campaign IS 'Daily aggregated usage costs and token spend per organization and campaign';


--
-- Name: usage_cost_daily_by_context; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.usage_cost_daily_by_context AS
 SELECT organization_id,
    usage_context,
    date(created_at) AS usage_date,
    sum(COALESCE(original_cost, (0)::numeric)) AS total_original_cost,
    sum(COALESCE(sellton_cost, (0)::numeric)) AS total_sellton_cost,
    sum(COALESCE(input_tokens, 0)) AS total_input_tokens,
    sum(COALESCE(output_tokens, 0)) AS total_output_tokens,
    sum(COALESCE(total_tokens, 0)) AS total_tokens,
    sum(COALESCE(api_calls, 0)) AS total_api_calls,
    count(DISTINCT provider) AS unique_providers,
    count(DISTINCT model_name) AS unique_models,
    count(DISTINCT campaign_id) AS unique_campaigns,
    count(DISTINCT session_id) AS unique_sessions,
    count(*) AS total_records,
    min(created_at) AS first_usage_at,
    max(created_at) AS last_usage_at
   FROM public.usage
  WHERE ((usage_context IS NOT NULL) AND (created_at IS NOT NULL))
  GROUP BY organization_id, usage_context, (date(created_at));


ALTER VIEW public.usage_cost_daily_by_context OWNER TO postgres;

--
-- Name: VIEW usage_cost_daily_by_context; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON VIEW public.usage_cost_daily_by_context IS 'Daily aggregated usage costs and token spend per organization and usage context';


--
-- Name: usage_cost_daily_with_split; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.usage_cost_daily_with_split AS
 SELECT organization_id,
    date(created_at) AS usage_date,
        CASE
            WHEN (campaign_id IS NOT NULL) THEN 'campaign'::text
            ELSE 'non_campaign'::text
        END AS cost_type,
    sum(COALESCE(original_cost, (0)::numeric)) AS total_original_cost,
    sum(COALESCE(sellton_cost, (0)::numeric)) AS total_sellton_cost,
    sum(COALESCE(input_tokens, 0)) AS total_input_tokens,
    sum(COALESCE(output_tokens, 0)) AS total_output_tokens,
    sum(COALESCE(total_tokens, 0)) AS total_tokens,
    sum(COALESCE(api_calls, 0)) AS total_api_calls,
    count(DISTINCT provider) AS unique_providers,
    count(DISTINCT model_name) AS unique_models,
    count(DISTINCT session_id) AS unique_sessions,
    count(DISTINCT campaign_id) AS unique_campaigns,
    count(*) AS total_records,
    min(created_at) AS first_usage_at,
    max(created_at) AS last_usage_at
   FROM public.usage
  WHERE (created_at IS NOT NULL)
  GROUP BY organization_id, (date(created_at)),
        CASE
            WHEN (campaign_id IS NOT NULL) THEN 'campaign'::text
            ELSE 'non_campaign'::text
        END;


ALTER VIEW public.usage_cost_daily_with_split OWNER TO postgres;

--
-- Name: VIEW usage_cost_daily_with_split; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON VIEW public.usage_cost_daily_with_split IS 'Daily aggregated usage costs split by campaign-related vs non-campaign-related costs';


--
-- Name: usage_cost_monthly; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.usage_cost_monthly AS
 SELECT organization_id,
    (date_trunc('month'::text, created_at))::date AS usage_month,
    sum(COALESCE(original_cost, (0)::numeric)) AS total_original_cost,
    sum(COALESCE(sellton_cost, (0)::numeric)) AS total_sellton_cost,
    sum(COALESCE(input_tokens, 0)) AS total_input_tokens,
    sum(COALESCE(output_tokens, 0)) AS total_output_tokens,
    sum(COALESCE(total_tokens, 0)) AS total_tokens,
    sum(COALESCE(api_calls, 0)) AS total_api_calls,
    count(DISTINCT provider) AS unique_providers,
    count(DISTINCT model_name) AS unique_models,
    count(DISTINCT session_id) AS unique_sessions,
    count(DISTINCT campaign_id) AS unique_campaigns,
    count(*) AS total_records,
    min(created_at) AS first_usage_at,
    max(created_at) AS last_usage_at
   FROM public.usage
  WHERE ((created_at IS NOT NULL) AND (campaign_id IS NOT NULL))
  GROUP BY organization_id, (date_trunc('month'::text, created_at));


ALTER VIEW public.usage_cost_monthly OWNER TO postgres;

--
-- Name: VIEW usage_cost_monthly; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON VIEW public.usage_cost_monthly IS 'Monthly aggregated usage costs and token spend per organization (excluding records without campaign_id)';


--
-- Name: usage_cost_monthly_by_campaign; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.usage_cost_monthly_by_campaign AS
 SELECT organization_id,
    campaign_id,
    (date_trunc('month'::text, created_at))::date AS usage_month,
    sum(COALESCE(original_cost, (0)::numeric)) AS total_original_cost,
    sum(COALESCE(sellton_cost, (0)::numeric)) AS total_sellton_cost,
    sum(COALESCE(input_tokens, 0)) AS total_input_tokens,
    sum(COALESCE(output_tokens, 0)) AS total_output_tokens,
    sum(COALESCE(total_tokens, 0)) AS total_tokens,
    sum(COALESCE(api_calls, 0)) AS total_api_calls,
    count(DISTINCT provider) AS unique_providers,
    count(DISTINCT model_name) AS unique_models,
    count(DISTINCT session_id) AS unique_sessions,
    count(*) AS total_records,
    min(created_at) AS first_usage_at,
    max(created_at) AS last_usage_at
   FROM public.usage
  WHERE ((created_at IS NOT NULL) AND (campaign_id IS NOT NULL))
  GROUP BY organization_id, campaign_id, (date_trunc('month'::text, created_at));


ALTER VIEW public.usage_cost_monthly_by_campaign OWNER TO postgres;

--
-- Name: VIEW usage_cost_monthly_by_campaign; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON VIEW public.usage_cost_monthly_by_campaign IS 'Monthly aggregated usage costs and token spend per organization and campaign';


--
-- Name: usage_cost_monthly_by_context; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.usage_cost_monthly_by_context AS
 SELECT organization_id,
    usage_context,
    (date_trunc('month'::text, created_at))::date AS usage_month,
    sum(COALESCE(original_cost, (0)::numeric)) AS total_original_cost,
    sum(COALESCE(sellton_cost, (0)::numeric)) AS total_sellton_cost,
    sum(COALESCE(input_tokens, 0)) AS total_input_tokens,
    sum(COALESCE(output_tokens, 0)) AS total_output_tokens,
    sum(COALESCE(total_tokens, 0)) AS total_tokens,
    sum(COALESCE(api_calls, 0)) AS total_api_calls,
    count(DISTINCT provider) AS unique_providers,
    count(DISTINCT model_name) AS unique_models,
    count(DISTINCT campaign_id) AS unique_campaigns,
    count(DISTINCT session_id) AS unique_sessions,
    count(*) AS total_records,
    min(created_at) AS first_usage_at,
    max(created_at) AS last_usage_at
   FROM public.usage
  WHERE ((usage_context IS NOT NULL) AND (created_at IS NOT NULL))
  GROUP BY organization_id, usage_context, (date_trunc('month'::text, created_at));


ALTER VIEW public.usage_cost_monthly_by_context OWNER TO postgres;

--
-- Name: VIEW usage_cost_monthly_by_context; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON VIEW public.usage_cost_monthly_by_context IS 'Monthly aggregated usage costs and token spend per organization and usage context';


--
-- Name: usage_cost_monthly_with_split; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.usage_cost_monthly_with_split AS
 SELECT organization_id,
    (date_trunc('month'::text, created_at))::date AS usage_month,
        CASE
            WHEN (campaign_id IS NOT NULL) THEN 'campaign'::text
            ELSE 'non_campaign'::text
        END AS cost_type,
    sum(COALESCE(original_cost, (0)::numeric)) AS total_original_cost,
    sum(COALESCE(sellton_cost, (0)::numeric)) AS total_sellton_cost,
    sum(COALESCE(input_tokens, 0)) AS total_input_tokens,
    sum(COALESCE(output_tokens, 0)) AS total_output_tokens,
    sum(COALESCE(total_tokens, 0)) AS total_tokens,
    sum(COALESCE(api_calls, 0)) AS total_api_calls,
    count(DISTINCT provider) AS unique_providers,
    count(DISTINCT model_name) AS unique_models,
    count(DISTINCT session_id) AS unique_sessions,
    count(DISTINCT campaign_id) AS unique_campaigns,
    count(*) AS total_records,
    min(created_at) AS first_usage_at,
    max(created_at) AS last_usage_at
   FROM public.usage
  WHERE (created_at IS NOT NULL)
  GROUP BY organization_id, (date_trunc('month'::text, created_at)),
        CASE
            WHEN (campaign_id IS NOT NULL) THEN 'campaign'::text
            ELSE 'non_campaign'::text
        END;


ALTER VIEW public.usage_cost_monthly_with_split OWNER TO postgres;

--
-- Name: VIEW usage_cost_monthly_with_split; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON VIEW public.usage_cost_monthly_with_split IS 'Monthly aggregated usage costs split by campaign-related vs non-campaign-related costs';


--
-- Name: usage_summary; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.usage_summary (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id text NOT NULL,
    provider text NOT NULL,
    model_name text,
    date date NOT NULL,
    total_api_calls integer DEFAULT 0 NOT NULL,
    total_input_tokens integer DEFAULT 0 NOT NULL,
    total_output_tokens integer DEFAULT 0 NOT NULL,
    total_tokens integer DEFAULT 0 NOT NULL,
    unique_sessions integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT usage_summary_total_api_calls_check CHECK ((total_api_calls >= 0)),
    CONSTRAINT usage_summary_total_input_tokens_check CHECK ((total_input_tokens >= 0)),
    CONSTRAINT usage_summary_total_output_tokens_check CHECK ((total_output_tokens >= 0)),
    CONSTRAINT usage_summary_total_tokens_check CHECK ((total_tokens >= 0)),
    CONSTRAINT usage_summary_unique_sessions_check CHECK ((unique_sessions >= 0))
);


ALTER TABLE public.usage_summary OWNER TO postgres;

--
-- Name: user; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."user" (
    id text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    email text NOT NULL
);


ALTER TABLE public."user" OWNER TO postgres;

--
-- Name: user_organizations; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_organizations (
    user_id text NOT NULL,
    organization_id text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.user_organizations OWNER TO postgres;

--
-- Name: messages; Type: TABLE; Schema: realtime; Owner: supabase_realtime_admin
--

CREATE TABLE realtime.messages (
    topic text NOT NULL,
    extension text NOT NULL,
    payload jsonb,
    event text,
    private boolean DEFAULT false,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    inserted_at timestamp without time zone DEFAULT now() NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL
)
PARTITION BY RANGE (inserted_at);


ALTER TABLE realtime.messages OWNER TO supabase_realtime_admin;

--
-- Name: messages_2026_02_13; Type: TABLE; Schema: realtime; Owner: supabase_admin
--

CREATE TABLE realtime.messages_2026_02_13 (
    topic text NOT NULL,
    extension text NOT NULL,
    payload jsonb,
    event text,
    private boolean DEFAULT false,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    inserted_at timestamp without time zone DEFAULT now() NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL
);


ALTER TABLE realtime.messages_2026_02_13 OWNER TO supabase_admin;

--
-- Name: messages_2026_02_14; Type: TABLE; Schema: realtime; Owner: supabase_admin
--

CREATE TABLE realtime.messages_2026_02_14 (
    topic text NOT NULL,
    extension text NOT NULL,
    payload jsonb,
    event text,
    private boolean DEFAULT false,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    inserted_at timestamp without time zone DEFAULT now() NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL
);


ALTER TABLE realtime.messages_2026_02_14 OWNER TO supabase_admin;

--
-- Name: messages_2026_02_15; Type: TABLE; Schema: realtime; Owner: supabase_admin
--

CREATE TABLE realtime.messages_2026_02_15 (
    topic text NOT NULL,
    extension text NOT NULL,
    payload jsonb,
    event text,
    private boolean DEFAULT false,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    inserted_at timestamp without time zone DEFAULT now() NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL
);


ALTER TABLE realtime.messages_2026_02_15 OWNER TO supabase_admin;

--
-- Name: messages_2026_02_16; Type: TABLE; Schema: realtime; Owner: supabase_admin
--

CREATE TABLE realtime.messages_2026_02_16 (
    topic text NOT NULL,
    extension text NOT NULL,
    payload jsonb,
    event text,
    private boolean DEFAULT false,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    inserted_at timestamp without time zone DEFAULT now() NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL
);


ALTER TABLE realtime.messages_2026_02_16 OWNER TO supabase_admin;

--
-- Name: messages_2026_02_17; Type: TABLE; Schema: realtime; Owner: supabase_admin
--

CREATE TABLE realtime.messages_2026_02_17 (
    topic text NOT NULL,
    extension text NOT NULL,
    payload jsonb,
    event text,
    private boolean DEFAULT false,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    inserted_at timestamp without time zone DEFAULT now() NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL
);


ALTER TABLE realtime.messages_2026_02_17 OWNER TO supabase_admin;

--
-- Name: messages_2026_02_18; Type: TABLE; Schema: realtime; Owner: supabase_admin
--

CREATE TABLE realtime.messages_2026_02_18 (
    topic text NOT NULL,
    extension text NOT NULL,
    payload jsonb,
    event text,
    private boolean DEFAULT false,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    inserted_at timestamp without time zone DEFAULT now() NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL
);


ALTER TABLE realtime.messages_2026_02_18 OWNER TO supabase_admin;

--
-- Name: messages_2026_02_19; Type: TABLE; Schema: realtime; Owner: supabase_admin
--

CREATE TABLE realtime.messages_2026_02_19 (
    topic text NOT NULL,
    extension text NOT NULL,
    payload jsonb,
    event text,
    private boolean DEFAULT false,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    inserted_at timestamp without time zone DEFAULT now() NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL
);


ALTER TABLE realtime.messages_2026_02_19 OWNER TO supabase_admin;

--
-- Name: schema_migrations; Type: TABLE; Schema: realtime; Owner: supabase_admin
--

CREATE TABLE realtime.schema_migrations (
    version bigint NOT NULL,
    inserted_at timestamp(0) without time zone
);


ALTER TABLE realtime.schema_migrations OWNER TO supabase_admin;

--
-- Name: subscription; Type: TABLE; Schema: realtime; Owner: supabase_admin
--

CREATE TABLE realtime.subscription (
    id bigint NOT NULL,
    subscription_id uuid NOT NULL,
    entity regclass NOT NULL,
    filters realtime.user_defined_filter[] DEFAULT '{}'::realtime.user_defined_filter[] NOT NULL,
    claims jsonb NOT NULL,
    claims_role regrole GENERATED ALWAYS AS (realtime.to_regrole((claims ->> 'role'::text))) STORED NOT NULL,
    created_at timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    action_filter text DEFAULT '*'::text,
    CONSTRAINT subscription_action_filter_check CHECK ((action_filter = ANY (ARRAY['*'::text, 'INSERT'::text, 'UPDATE'::text, 'DELETE'::text])))
);


ALTER TABLE realtime.subscription OWNER TO supabase_admin;

--
-- Name: subscription_id_seq; Type: SEQUENCE; Schema: realtime; Owner: supabase_admin
--

ALTER TABLE realtime.subscription ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME realtime.subscription_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: buckets; Type: TABLE; Schema: storage; Owner: supabase_storage_admin
--

CREATE TABLE storage.buckets (
    id text NOT NULL,
    name text NOT NULL,
    owner uuid,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    public boolean DEFAULT false,
    avif_autodetection boolean DEFAULT false,
    file_size_limit bigint,
    allowed_mime_types text[],
    owner_id text,
    type storage.buckettype DEFAULT 'STANDARD'::storage.buckettype NOT NULL
);


ALTER TABLE storage.buckets OWNER TO supabase_storage_admin;

--
-- Name: COLUMN buckets.owner; Type: COMMENT; Schema: storage; Owner: supabase_storage_admin
--

COMMENT ON COLUMN storage.buckets.owner IS 'Field is deprecated, use owner_id instead';


--
-- Name: buckets_analytics; Type: TABLE; Schema: storage; Owner: supabase_storage_admin
--

CREATE TABLE storage.buckets_analytics (
    name text NOT NULL,
    type storage.buckettype DEFAULT 'ANALYTICS'::storage.buckettype NOT NULL,
    format text DEFAULT 'ICEBERG'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    deleted_at timestamp with time zone
);


ALTER TABLE storage.buckets_analytics OWNER TO supabase_storage_admin;

--
-- Name: buckets_vectors; Type: TABLE; Schema: storage; Owner: supabase_storage_admin
--

CREATE TABLE storage.buckets_vectors (
    id text NOT NULL,
    type storage.buckettype DEFAULT 'VECTOR'::storage.buckettype NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE storage.buckets_vectors OWNER TO supabase_storage_admin;

--
-- Name: migrations; Type: TABLE; Schema: storage; Owner: supabase_storage_admin
--

CREATE TABLE storage.migrations (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    hash character varying(40) NOT NULL,
    executed_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE storage.migrations OWNER TO supabase_storage_admin;

--
-- Name: objects; Type: TABLE; Schema: storage; Owner: supabase_storage_admin
--

CREATE TABLE storage.objects (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    bucket_id text,
    name text,
    owner uuid,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    last_accessed_at timestamp with time zone DEFAULT now(),
    metadata jsonb,
    path_tokens text[] GENERATED ALWAYS AS (string_to_array(name, '/'::text)) STORED,
    version text,
    owner_id text,
    user_metadata jsonb
);


ALTER TABLE storage.objects OWNER TO supabase_storage_admin;

--
-- Name: COLUMN objects.owner; Type: COMMENT; Schema: storage; Owner: supabase_storage_admin
--

COMMENT ON COLUMN storage.objects.owner IS 'Field is deprecated, use owner_id instead';


--
-- Name: s3_multipart_uploads; Type: TABLE; Schema: storage; Owner: supabase_storage_admin
--

CREATE TABLE storage.s3_multipart_uploads (
    id text NOT NULL,
    in_progress_size bigint DEFAULT 0 NOT NULL,
    upload_signature text NOT NULL,
    bucket_id text NOT NULL,
    key text NOT NULL COLLATE pg_catalog."C",
    version text NOT NULL,
    owner_id text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    user_metadata jsonb
);


ALTER TABLE storage.s3_multipart_uploads OWNER TO supabase_storage_admin;

--
-- Name: s3_multipart_uploads_parts; Type: TABLE; Schema: storage; Owner: supabase_storage_admin
--

CREATE TABLE storage.s3_multipart_uploads_parts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    upload_id text NOT NULL,
    size bigint DEFAULT 0 NOT NULL,
    part_number integer NOT NULL,
    bucket_id text NOT NULL,
    key text NOT NULL COLLATE pg_catalog."C",
    etag text NOT NULL,
    owner_id text,
    version text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE storage.s3_multipart_uploads_parts OWNER TO supabase_storage_admin;

--
-- Name: vector_indexes; Type: TABLE; Schema: storage; Owner: supabase_storage_admin
--

CREATE TABLE storage.vector_indexes (
    id text DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL COLLATE pg_catalog."C",
    bucket_id text NOT NULL,
    data_type text NOT NULL,
    dimension integer NOT NULL,
    distance_metric text NOT NULL,
    metadata_configuration jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE storage.vector_indexes OWNER TO supabase_storage_admin;

--
-- Name: messages_2026_02_13; Type: TABLE ATTACH; Schema: realtime; Owner: supabase_admin
--

ALTER TABLE ONLY realtime.messages ATTACH PARTITION realtime.messages_2026_02_13 FOR VALUES FROM ('2026-02-13 00:00:00') TO ('2026-02-14 00:00:00');


--
-- Name: messages_2026_02_14; Type: TABLE ATTACH; Schema: realtime; Owner: supabase_admin
--

ALTER TABLE ONLY realtime.messages ATTACH PARTITION realtime.messages_2026_02_14 FOR VALUES FROM ('2026-02-14 00:00:00') TO ('2026-02-15 00:00:00');


--
-- Name: messages_2026_02_15; Type: TABLE ATTACH; Schema: realtime; Owner: supabase_admin
--

ALTER TABLE ONLY realtime.messages ATTACH PARTITION realtime.messages_2026_02_15 FOR VALUES FROM ('2026-02-15 00:00:00') TO ('2026-02-16 00:00:00');


--
-- Name: messages_2026_02_16; Type: TABLE ATTACH; Schema: realtime; Owner: supabase_admin
--

ALTER TABLE ONLY realtime.messages ATTACH PARTITION realtime.messages_2026_02_16 FOR VALUES FROM ('2026-02-16 00:00:00') TO ('2026-02-17 00:00:00');


--
-- Name: messages_2026_02_17; Type: TABLE ATTACH; Schema: realtime; Owner: supabase_admin
--

ALTER TABLE ONLY realtime.messages ATTACH PARTITION realtime.messages_2026_02_17 FOR VALUES FROM ('2026-02-17 00:00:00') TO ('2026-02-18 00:00:00');


--
-- Name: messages_2026_02_18; Type: TABLE ATTACH; Schema: realtime; Owner: supabase_admin
--

ALTER TABLE ONLY realtime.messages ATTACH PARTITION realtime.messages_2026_02_18 FOR VALUES FROM ('2026-02-18 00:00:00') TO ('2026-02-19 00:00:00');


--
-- Name: messages_2026_02_19; Type: TABLE ATTACH; Schema: realtime; Owner: supabase_admin
--

ALTER TABLE ONLY realtime.messages ATTACH PARTITION realtime.messages_2026_02_19 FOR VALUES FROM ('2026-02-19 00:00:00') TO ('2026-02-20 00:00:00');


--
-- Name: refresh_tokens id; Type: DEFAULT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.refresh_tokens ALTER COLUMN id SET DEFAULT nextval('auth.refresh_tokens_id_seq'::regclass);


--
-- Name: feedback id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.feedback ALTER COLUMN id SET DEFAULT nextval('public.feedback_id_seq'::regclass);


--
-- Name: interviewer id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.interviewer ALTER COLUMN id SET DEFAULT nextval('public.interviewer_id_seq'::regclass);


--
-- Name: response id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.response ALTER COLUMN id SET DEFAULT nextval('public.response_id_seq'::regclass);


--
-- Name: style_guidelines id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.style_guidelines ALTER COLUMN id SET DEFAULT nextval('public.style_guidelines_id_seq'::regclass);


--
-- Name: token_usage id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.token_usage ALTER COLUMN id SET DEFAULT nextval('public.token_usage_id_seq'::regclass);


--
-- Name: mfa_amr_claims amr_id_pk; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.mfa_amr_claims
    ADD CONSTRAINT amr_id_pk PRIMARY KEY (id);


--
-- Name: audit_log_entries audit_log_entries_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.audit_log_entries
    ADD CONSTRAINT audit_log_entries_pkey PRIMARY KEY (id);


--
-- Name: flow_state flow_state_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.flow_state
    ADD CONSTRAINT flow_state_pkey PRIMARY KEY (id);


--
-- Name: identities identities_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.identities
    ADD CONSTRAINT identities_pkey PRIMARY KEY (id);


--
-- Name: identities identities_provider_id_provider_unique; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.identities
    ADD CONSTRAINT identities_provider_id_provider_unique UNIQUE (provider_id, provider);


--
-- Name: instances instances_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.instances
    ADD CONSTRAINT instances_pkey PRIMARY KEY (id);


--
-- Name: mfa_amr_claims mfa_amr_claims_session_id_authentication_method_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.mfa_amr_claims
    ADD CONSTRAINT mfa_amr_claims_session_id_authentication_method_pkey UNIQUE (session_id, authentication_method);


--
-- Name: mfa_challenges mfa_challenges_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.mfa_challenges
    ADD CONSTRAINT mfa_challenges_pkey PRIMARY KEY (id);


--
-- Name: mfa_factors mfa_factors_last_challenged_at_key; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.mfa_factors
    ADD CONSTRAINT mfa_factors_last_challenged_at_key UNIQUE (last_challenged_at);


--
-- Name: mfa_factors mfa_factors_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.mfa_factors
    ADD CONSTRAINT mfa_factors_pkey PRIMARY KEY (id);


--
-- Name: oauth_authorizations oauth_authorizations_authorization_code_key; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.oauth_authorizations
    ADD CONSTRAINT oauth_authorizations_authorization_code_key UNIQUE (authorization_code);


--
-- Name: oauth_authorizations oauth_authorizations_authorization_id_key; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.oauth_authorizations
    ADD CONSTRAINT oauth_authorizations_authorization_id_key UNIQUE (authorization_id);


--
-- Name: oauth_authorizations oauth_authorizations_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.oauth_authorizations
    ADD CONSTRAINT oauth_authorizations_pkey PRIMARY KEY (id);


--
-- Name: oauth_client_states oauth_client_states_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.oauth_client_states
    ADD CONSTRAINT oauth_client_states_pkey PRIMARY KEY (id);


--
-- Name: oauth_clients oauth_clients_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.oauth_clients
    ADD CONSTRAINT oauth_clients_pkey PRIMARY KEY (id);


--
-- Name: oauth_consents oauth_consents_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.oauth_consents
    ADD CONSTRAINT oauth_consents_pkey PRIMARY KEY (id);


--
-- Name: oauth_consents oauth_consents_user_client_unique; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.oauth_consents
    ADD CONSTRAINT oauth_consents_user_client_unique UNIQUE (user_id, client_id);


--
-- Name: one_time_tokens one_time_tokens_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.one_time_tokens
    ADD CONSTRAINT one_time_tokens_pkey PRIMARY KEY (id);


--
-- Name: refresh_tokens refresh_tokens_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.refresh_tokens
    ADD CONSTRAINT refresh_tokens_pkey PRIMARY KEY (id);


--
-- Name: refresh_tokens refresh_tokens_token_unique; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.refresh_tokens
    ADD CONSTRAINT refresh_tokens_token_unique UNIQUE (token);


--
-- Name: saml_providers saml_providers_entity_id_key; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.saml_providers
    ADD CONSTRAINT saml_providers_entity_id_key UNIQUE (entity_id);


--
-- Name: saml_providers saml_providers_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.saml_providers
    ADD CONSTRAINT saml_providers_pkey PRIMARY KEY (id);


--
-- Name: saml_relay_states saml_relay_states_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.saml_relay_states
    ADD CONSTRAINT saml_relay_states_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: sso_domains sso_domains_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.sso_domains
    ADD CONSTRAINT sso_domains_pkey PRIMARY KEY (id);


--
-- Name: sso_providers sso_providers_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.sso_providers
    ADD CONSTRAINT sso_providers_pkey PRIMARY KEY (id);


--
-- Name: users users_phone_key; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.users
    ADD CONSTRAINT users_phone_key UNIQUE (phone);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: campaign_activities campaign_activities_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.campaign_activities
    ADD CONSTRAINT campaign_activities_pkey PRIMARY KEY (id);


--
-- Name: campaign_companies campaign_companies_campaign_id_company_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.campaign_companies
    ADD CONSTRAINT campaign_companies_campaign_id_company_id_key UNIQUE (campaign_id, company_id);


--
-- Name: campaign_companies campaign_companies_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.campaign_companies
    ADD CONSTRAINT campaign_companies_pkey PRIMARY KEY (id);


--
-- Name: campaign_emails campaign_emails_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.campaign_emails
    ADD CONSTRAINT campaign_emails_pkey PRIMARY KEY (id);


--
-- Name: campaign_files campaign_files_campaign_id_file_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.campaign_files
    ADD CONSTRAINT campaign_files_campaign_id_file_id_key UNIQUE (campaign_id, file_id);


--
-- Name: campaign_files campaign_files_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.campaign_files
    ADD CONSTRAINT campaign_files_pkey PRIMARY KEY (id);


--
-- Name: campaign_seed_companies campaign_seed_companies_campaign_id_seed_company_url_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.campaign_seed_companies
    ADD CONSTRAINT campaign_seed_companies_campaign_id_seed_company_url_key UNIQUE (campaign_id, seed_company_url);


--
-- Name: campaign_seed_companies campaign_seed_companies_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.campaign_seed_companies
    ADD CONSTRAINT campaign_seed_companies_pkey PRIMARY KEY (id);


--
-- Name: campaigns campaigns_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.campaigns
    ADD CONSTRAINT campaigns_pkey PRIMARY KEY (id);


--
-- Name: companies companies_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.companies
    ADD CONSTRAINT companies_pkey PRIMARY KEY (id);


--
-- Name: company_activities company_activities_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_activities
    ADD CONSTRAINT company_activities_pkey PRIMARY KEY (id);


--
-- Name: company_contacts company_contacts_company_id_contact_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_contacts
    ADD CONSTRAINT company_contacts_company_id_contact_id_key UNIQUE (company_id, contact_id);


--
-- Name: company_contacts company_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_contacts
    ADD CONSTRAINT company_contacts_pkey PRIMARY KEY (id);


--
-- Name: company_research_jobs company_research_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_research_jobs
    ADD CONSTRAINT company_research_jobs_pkey PRIMARY KEY (id);


--
-- Name: contact_activities contact_activities_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.contact_activities
    ADD CONSTRAINT contact_activities_pkey PRIMARY KEY (id);


--
-- Name: contact_channels contact_channels_contact_id_channel_type_channel_value_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.contact_channels
    ADD CONSTRAINT contact_channels_contact_id_channel_type_channel_value_key UNIQUE (contact_id, channel_type, channel_value);


--
-- Name: contact_channels contact_channels_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.contact_channels
    ADD CONSTRAINT contact_channels_pkey PRIMARY KEY (id);


--
-- Name: contact_notes contact_notes_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.contact_notes
    ADD CONSTRAINT contact_notes_pkey PRIMARY KEY (id);


--
-- Name: contacts contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.contacts
    ADD CONSTRAINT contacts_pkey PRIMARY KEY (id);


--
-- Name: conversation_messages conversation_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.conversation_messages
    ADD CONSTRAINT conversation_messages_pkey PRIMARY KEY (id);


--
-- Name: conversations conversations_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_pkey PRIMARY KEY (id);


--
-- Name: deep_research_settings deep_research_settings_organization_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.deep_research_settings
    ADD CONSTRAINT deep_research_settings_organization_id_key UNIQUE (organization_id);


--
-- Name: deep_research_settings deep_research_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.deep_research_settings
    ADD CONSTRAINT deep_research_settings_pkey PRIMARY KEY (id);


--
-- Name: document_access_events document_access_events_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.document_access_events
    ADD CONSTRAINT document_access_events_pkey PRIMARY KEY (id);


--
-- Name: document_short_urls document_short_urls_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.document_short_urls
    ADD CONSTRAINT document_short_urls_pkey PRIMARY KEY (id);


--
-- Name: document_short_urls document_short_urls_short_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.document_short_urls
    ADD CONSTRAINT document_short_urls_short_code_key UNIQUE (short_code);


--
-- Name: feedback feedback_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.feedback
    ADD CONSTRAINT feedback_pkey PRIMARY KEY (id);


--
-- Name: icp_profiles icp_profiles_organization_id_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.icp_profiles
    ADD CONSTRAINT icp_profiles_organization_id_name_key UNIQUE (organization_id, name);


--
-- Name: icp_profiles icp_profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.icp_profiles
    ADD CONSTRAINT icp_profiles_pkey PRIMARY KEY (id);


--
-- Name: interview interview_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.interview
    ADD CONSTRAINT interview_pkey PRIMARY KEY (id);


--
-- Name: interviewer interviewer_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.interviewer
    ADD CONSTRAINT interviewer_pkey PRIMARY KEY (id);


--
-- Name: organization_files_chunks organization_files_chunks_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.organization_files_chunks
    ADD CONSTRAINT organization_files_chunks_pkey PRIMARY KEY (id);


--
-- Name: organization_files organization_files_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.organization_files
    ADD CONSTRAINT organization_files_pkey PRIMARY KEY (id);


--
-- Name: organization_icp_linkedin_urls organization_icp_linkedin_urls_organization_id_url_url_type_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.organization_icp_linkedin_urls
    ADD CONSTRAINT organization_icp_linkedin_urls_organization_id_url_url_type_key UNIQUE (organization_id, url, url_type);


--
-- Name: organization_icp_linkedin_urls organization_icp_linkedin_urls_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.organization_icp_linkedin_urls
    ADD CONSTRAINT organization_icp_linkedin_urls_pkey PRIMARY KEY (id);


--
-- Name: organization organization_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.organization
    ADD CONSTRAINT organization_pkey PRIMARY KEY (id);


--
-- Name: organization_settings organization_settings_api_key_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.organization_settings
    ADD CONSTRAINT organization_settings_api_key_key UNIQUE (api_key);


--
-- Name: organization_settings organization_settings_organization_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.organization_settings
    ADD CONSTRAINT organization_settings_organization_id_key UNIQUE (organization_id);


--
-- Name: organization_settings organization_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.organization_settings
    ADD CONSTRAINT organization_settings_pkey PRIMARY KEY (id);


--
-- Name: response response_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.response
    ADD CONSTRAINT response_pkey PRIMARY KEY (id);


--
-- Name: style_guidelines style_guidelines_organization_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.style_guidelines
    ADD CONSTRAINT style_guidelines_organization_id_key UNIQUE (organization_id);


--
-- Name: style_guidelines style_guidelines_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.style_guidelines
    ADD CONSTRAINT style_guidelines_pkey PRIMARY KEY (id);


--
-- Name: system_config system_config_key_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.system_config
    ADD CONSTRAINT system_config_key_key UNIQUE (key);


--
-- Name: system_config system_config_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.system_config
    ADD CONSTRAINT system_config_pkey PRIMARY KEY (id);


--
-- Name: tasks tasks_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT tasks_pkey PRIMARY KEY (id);


--
-- Name: token_usage token_usage_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.token_usage
    ADD CONSTRAINT token_usage_pkey PRIMARY KEY (id);


--
-- Name: usage usage_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.usage
    ADD CONSTRAINT usage_pkey PRIMARY KEY (id);


--
-- Name: usage_summary usage_summary_organization_id_provider_model_name_date_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.usage_summary
    ADD CONSTRAINT usage_summary_organization_id_provider_model_name_date_key UNIQUE (organization_id, provider, model_name, date);


--
-- Name: usage_summary usage_summary_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.usage_summary
    ADD CONSTRAINT usage_summary_pkey PRIMARY KEY (id);


--
-- Name: user user_email_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."user"
    ADD CONSTRAINT user_email_key UNIQUE (email);


--
-- Name: user_organizations user_organizations_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_organizations
    ADD CONSTRAINT user_organizations_pkey PRIMARY KEY (user_id, organization_id);


--
-- Name: user user_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."user"
    ADD CONSTRAINT user_pkey PRIMARY KEY (id);


--
-- Name: messages messages_pkey; Type: CONSTRAINT; Schema: realtime; Owner: supabase_realtime_admin
--

ALTER TABLE ONLY realtime.messages
    ADD CONSTRAINT messages_pkey PRIMARY KEY (id, inserted_at);


--
-- Name: messages_2026_02_13 messages_2026_02_13_pkey; Type: CONSTRAINT; Schema: realtime; Owner: supabase_admin
--

ALTER TABLE ONLY realtime.messages_2026_02_13
    ADD CONSTRAINT messages_2026_02_13_pkey PRIMARY KEY (id, inserted_at);


--
-- Name: messages_2026_02_14 messages_2026_02_14_pkey; Type: CONSTRAINT; Schema: realtime; Owner: supabase_admin
--

ALTER TABLE ONLY realtime.messages_2026_02_14
    ADD CONSTRAINT messages_2026_02_14_pkey PRIMARY KEY (id, inserted_at);


--
-- Name: messages_2026_02_15 messages_2026_02_15_pkey; Type: CONSTRAINT; Schema: realtime; Owner: supabase_admin
--

ALTER TABLE ONLY realtime.messages_2026_02_15
    ADD CONSTRAINT messages_2026_02_15_pkey PRIMARY KEY (id, inserted_at);


--
-- Name: messages_2026_02_16 messages_2026_02_16_pkey; Type: CONSTRAINT; Schema: realtime; Owner: supabase_admin
--

ALTER TABLE ONLY realtime.messages_2026_02_16
    ADD CONSTRAINT messages_2026_02_16_pkey PRIMARY KEY (id, inserted_at);


--
-- Name: messages_2026_02_17 messages_2026_02_17_pkey; Type: CONSTRAINT; Schema: realtime; Owner: supabase_admin
--

ALTER TABLE ONLY realtime.messages_2026_02_17
    ADD CONSTRAINT messages_2026_02_17_pkey PRIMARY KEY (id, inserted_at);


--
-- Name: messages_2026_02_18 messages_2026_02_18_pkey; Type: CONSTRAINT; Schema: realtime; Owner: supabase_admin
--

ALTER TABLE ONLY realtime.messages_2026_02_18
    ADD CONSTRAINT messages_2026_02_18_pkey PRIMARY KEY (id, inserted_at);


--
-- Name: messages_2026_02_19 messages_2026_02_19_pkey; Type: CONSTRAINT; Schema: realtime; Owner: supabase_admin
--

ALTER TABLE ONLY realtime.messages_2026_02_19
    ADD CONSTRAINT messages_2026_02_19_pkey PRIMARY KEY (id, inserted_at);


--
-- Name: subscription pk_subscription; Type: CONSTRAINT; Schema: realtime; Owner: supabase_admin
--

ALTER TABLE ONLY realtime.subscription
    ADD CONSTRAINT pk_subscription PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: realtime; Owner: supabase_admin
--

ALTER TABLE ONLY realtime.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: buckets_analytics buckets_analytics_pkey; Type: CONSTRAINT; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE ONLY storage.buckets_analytics
    ADD CONSTRAINT buckets_analytics_pkey PRIMARY KEY (id);


--
-- Name: buckets buckets_pkey; Type: CONSTRAINT; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE ONLY storage.buckets
    ADD CONSTRAINT buckets_pkey PRIMARY KEY (id);


--
-- Name: buckets_vectors buckets_vectors_pkey; Type: CONSTRAINT; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE ONLY storage.buckets_vectors
    ADD CONSTRAINT buckets_vectors_pkey PRIMARY KEY (id);


--
-- Name: migrations migrations_name_key; Type: CONSTRAINT; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE ONLY storage.migrations
    ADD CONSTRAINT migrations_name_key UNIQUE (name);


--
-- Name: migrations migrations_pkey; Type: CONSTRAINT; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE ONLY storage.migrations
    ADD CONSTRAINT migrations_pkey PRIMARY KEY (id);


--
-- Name: objects objects_pkey; Type: CONSTRAINT; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE ONLY storage.objects
    ADD CONSTRAINT objects_pkey PRIMARY KEY (id);


--
-- Name: s3_multipart_uploads_parts s3_multipart_uploads_parts_pkey; Type: CONSTRAINT; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE ONLY storage.s3_multipart_uploads_parts
    ADD CONSTRAINT s3_multipart_uploads_parts_pkey PRIMARY KEY (id);


--
-- Name: s3_multipart_uploads s3_multipart_uploads_pkey; Type: CONSTRAINT; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE ONLY storage.s3_multipart_uploads
    ADD CONSTRAINT s3_multipart_uploads_pkey PRIMARY KEY (id);


--
-- Name: vector_indexes vector_indexes_pkey; Type: CONSTRAINT; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE ONLY storage.vector_indexes
    ADD CONSTRAINT vector_indexes_pkey PRIMARY KEY (id);


--
-- Name: audit_logs_instance_id_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX audit_logs_instance_id_idx ON auth.audit_log_entries USING btree (instance_id);


--
-- Name: confirmation_token_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE UNIQUE INDEX confirmation_token_idx ON auth.users USING btree (confirmation_token) WHERE ((confirmation_token)::text !~ '^[0-9 ]*$'::text);


--
-- Name: email_change_token_current_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE UNIQUE INDEX email_change_token_current_idx ON auth.users USING btree (email_change_token_current) WHERE ((email_change_token_current)::text !~ '^[0-9 ]*$'::text);


--
-- Name: email_change_token_new_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE UNIQUE INDEX email_change_token_new_idx ON auth.users USING btree (email_change_token_new) WHERE ((email_change_token_new)::text !~ '^[0-9 ]*$'::text);


--
-- Name: factor_id_created_at_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX factor_id_created_at_idx ON auth.mfa_factors USING btree (user_id, created_at);


--
-- Name: flow_state_created_at_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX flow_state_created_at_idx ON auth.flow_state USING btree (created_at DESC);


--
-- Name: identities_email_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX identities_email_idx ON auth.identities USING btree (email text_pattern_ops);


--
-- Name: INDEX identities_email_idx; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON INDEX auth.identities_email_idx IS 'Auth: Ensures indexed queries on the email column';


--
-- Name: identities_user_id_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX identities_user_id_idx ON auth.identities USING btree (user_id);


--
-- Name: idx_auth_code; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX idx_auth_code ON auth.flow_state USING btree (auth_code);


--
-- Name: idx_oauth_client_states_created_at; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX idx_oauth_client_states_created_at ON auth.oauth_client_states USING btree (created_at);


--
-- Name: idx_user_id_auth_method; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX idx_user_id_auth_method ON auth.flow_state USING btree (user_id, authentication_method);


--
-- Name: mfa_challenge_created_at_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX mfa_challenge_created_at_idx ON auth.mfa_challenges USING btree (created_at DESC);


--
-- Name: mfa_factors_user_friendly_name_unique; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE UNIQUE INDEX mfa_factors_user_friendly_name_unique ON auth.mfa_factors USING btree (friendly_name, user_id) WHERE (TRIM(BOTH FROM friendly_name) <> ''::text);


--
-- Name: mfa_factors_user_id_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX mfa_factors_user_id_idx ON auth.mfa_factors USING btree (user_id);


--
-- Name: oauth_auth_pending_exp_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX oauth_auth_pending_exp_idx ON auth.oauth_authorizations USING btree (expires_at) WHERE (status = 'pending'::auth.oauth_authorization_status);


--
-- Name: oauth_clients_deleted_at_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX oauth_clients_deleted_at_idx ON auth.oauth_clients USING btree (deleted_at);


--
-- Name: oauth_consents_active_client_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX oauth_consents_active_client_idx ON auth.oauth_consents USING btree (client_id) WHERE (revoked_at IS NULL);


--
-- Name: oauth_consents_active_user_client_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX oauth_consents_active_user_client_idx ON auth.oauth_consents USING btree (user_id, client_id) WHERE (revoked_at IS NULL);


--
-- Name: oauth_consents_user_order_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX oauth_consents_user_order_idx ON auth.oauth_consents USING btree (user_id, granted_at DESC);


--
-- Name: one_time_tokens_relates_to_hash_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX one_time_tokens_relates_to_hash_idx ON auth.one_time_tokens USING hash (relates_to);


--
-- Name: one_time_tokens_token_hash_hash_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX one_time_tokens_token_hash_hash_idx ON auth.one_time_tokens USING hash (token_hash);


--
-- Name: one_time_tokens_user_id_token_type_key; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE UNIQUE INDEX one_time_tokens_user_id_token_type_key ON auth.one_time_tokens USING btree (user_id, token_type);


--
-- Name: reauthentication_token_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE UNIQUE INDEX reauthentication_token_idx ON auth.users USING btree (reauthentication_token) WHERE ((reauthentication_token)::text !~ '^[0-9 ]*$'::text);


--
-- Name: recovery_token_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE UNIQUE INDEX recovery_token_idx ON auth.users USING btree (recovery_token) WHERE ((recovery_token)::text !~ '^[0-9 ]*$'::text);


--
-- Name: refresh_tokens_instance_id_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX refresh_tokens_instance_id_idx ON auth.refresh_tokens USING btree (instance_id);


--
-- Name: refresh_tokens_instance_id_user_id_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX refresh_tokens_instance_id_user_id_idx ON auth.refresh_tokens USING btree (instance_id, user_id);


--
-- Name: refresh_tokens_parent_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX refresh_tokens_parent_idx ON auth.refresh_tokens USING btree (parent);


--
-- Name: refresh_tokens_session_id_revoked_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX refresh_tokens_session_id_revoked_idx ON auth.refresh_tokens USING btree (session_id, revoked);


--
-- Name: refresh_tokens_updated_at_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX refresh_tokens_updated_at_idx ON auth.refresh_tokens USING btree (updated_at DESC);


--
-- Name: saml_providers_sso_provider_id_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX saml_providers_sso_provider_id_idx ON auth.saml_providers USING btree (sso_provider_id);


--
-- Name: saml_relay_states_created_at_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX saml_relay_states_created_at_idx ON auth.saml_relay_states USING btree (created_at DESC);


--
-- Name: saml_relay_states_for_email_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX saml_relay_states_for_email_idx ON auth.saml_relay_states USING btree (for_email);


--
-- Name: saml_relay_states_sso_provider_id_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX saml_relay_states_sso_provider_id_idx ON auth.saml_relay_states USING btree (sso_provider_id);


--
-- Name: sessions_not_after_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX sessions_not_after_idx ON auth.sessions USING btree (not_after DESC);


--
-- Name: sessions_oauth_client_id_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX sessions_oauth_client_id_idx ON auth.sessions USING btree (oauth_client_id);


--
-- Name: sessions_user_id_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX sessions_user_id_idx ON auth.sessions USING btree (user_id);


--
-- Name: sso_domains_domain_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE UNIQUE INDEX sso_domains_domain_idx ON auth.sso_domains USING btree (lower(domain));


--
-- Name: sso_domains_sso_provider_id_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX sso_domains_sso_provider_id_idx ON auth.sso_domains USING btree (sso_provider_id);


--
-- Name: sso_providers_resource_id_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE UNIQUE INDEX sso_providers_resource_id_idx ON auth.sso_providers USING btree (lower(resource_id));


--
-- Name: sso_providers_resource_id_pattern_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX sso_providers_resource_id_pattern_idx ON auth.sso_providers USING btree (resource_id text_pattern_ops);


--
-- Name: unique_phone_factor_per_user; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE UNIQUE INDEX unique_phone_factor_per_user ON auth.mfa_factors USING btree (user_id, phone);


--
-- Name: user_id_created_at_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX user_id_created_at_idx ON auth.sessions USING btree (user_id, created_at);


--
-- Name: users_email_partial_key; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE UNIQUE INDEX users_email_partial_key ON auth.users USING btree (email) WHERE (is_sso_user = false);


--
-- Name: INDEX users_email_partial_key; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON INDEX auth.users_email_partial_key IS 'Auth: A partial unique index that applies only when is_sso_user is false';


--
-- Name: users_instance_id_email_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX users_instance_id_email_idx ON auth.users USING btree (instance_id, lower((email)::text));


--
-- Name: users_instance_id_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX users_instance_id_idx ON auth.users USING btree (instance_id);


--
-- Name: users_is_anonymous_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX users_is_anonymous_idx ON auth.users USING btree (is_anonymous);


--
-- Name: idx_access_events_accessed_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_access_events_accessed_at ON public.document_access_events USING btree (accessed_at DESC);


--
-- Name: idx_access_events_contact; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_access_events_contact ON public.document_access_events USING btree (contact_id);


--
-- Name: idx_access_events_event_type; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_access_events_event_type ON public.document_access_events USING btree (event_type);


--
-- Name: idx_access_events_org; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_access_events_org ON public.document_access_events USING btree (organization_id);


--
-- Name: idx_access_events_short_url; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_access_events_short_url ON public.document_access_events USING btree (short_url_id);


--
-- Name: idx_campaign_activities_campaign_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_campaign_activities_campaign_id ON public.campaign_activities USING btree (campaign_id);


--
-- Name: idx_campaign_activities_contact_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_campaign_activities_contact_id ON public.campaign_activities USING btree (contact_id) WHERE (contact_id IS NOT NULL);


--
-- Name: idx_campaign_activities_meetings; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_campaign_activities_meetings ON public.campaign_activities USING btree (campaign_id, activity_type) WHERE (activity_type = 'meeting_booked'::text);


--
-- Name: idx_campaign_activities_occurred_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_campaign_activities_occurred_at ON public.campaign_activities USING btree (campaign_id, occurred_at DESC);


--
-- Name: idx_campaign_activities_org_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_campaign_activities_org_id ON public.campaign_activities USING btree (organization_id);


--
-- Name: idx_campaign_companies_batch_lookup; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_campaign_companies_batch_lookup ON public.campaign_companies USING btree (organization_id, campaign_id, company_id);


--
-- Name: idx_campaign_companies_blocked_by_icp; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_campaign_companies_blocked_by_icp ON public.campaign_companies USING btree (blocked_by_icp) WHERE (blocked_by_icp = true);


--
-- Name: idx_campaign_companies_campaign_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_campaign_companies_campaign_id ON public.campaign_companies USING btree (campaign_id);


--
-- Name: idx_campaign_companies_company_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_campaign_companies_company_id ON public.campaign_companies USING btree (company_id);


--
-- Name: idx_campaign_companies_icp_profile_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_campaign_companies_icp_profile_id ON public.campaign_companies USING btree (icp_profile_id_used);


--
-- Name: idx_campaign_companies_org_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_campaign_companies_org_id ON public.campaign_companies USING btree (organization_id);


--
-- Name: idx_campaign_emails_campaign_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_campaign_emails_campaign_id ON public.campaign_emails USING btree (campaign_id);


--
-- Name: idx_campaign_emails_contact_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_campaign_emails_contact_id ON public.campaign_emails USING btree (contact_id);


--
-- Name: idx_campaign_emails_message_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_campaign_emails_message_id ON public.campaign_emails USING btree (message_id) WHERE (message_id IS NOT NULL);


--
-- Name: idx_campaign_emails_opened; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_campaign_emails_opened ON public.campaign_emails USING btree (campaign_id, opened_at) WHERE (opened_at IS NOT NULL);


--
-- Name: idx_campaign_emails_org_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_campaign_emails_org_id ON public.campaign_emails USING btree (organization_id);


--
-- Name: idx_campaign_emails_replied; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_campaign_emails_replied ON public.campaign_emails USING btree (campaign_id, replied_at) WHERE (replied_at IS NOT NULL);


--
-- Name: idx_campaign_emails_sent_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_campaign_emails_sent_at ON public.campaign_emails USING btree (campaign_id, sent_at) WHERE (sent_at IS NOT NULL);


--
-- Name: idx_campaign_emails_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_campaign_emails_status ON public.campaign_emails USING btree (campaign_id, status);


--
-- Name: idx_campaign_emails_thread_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_campaign_emails_thread_id ON public.campaign_emails USING btree (thread_id) WHERE (thread_id IS NOT NULL);


--
-- Name: idx_campaign_files_campaign_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_campaign_files_campaign_id ON public.campaign_files USING btree (campaign_id);


--
-- Name: idx_campaign_files_created_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_campaign_files_created_at ON public.campaign_files USING btree (created_at DESC);


--
-- Name: idx_campaign_files_file_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_campaign_files_file_id ON public.campaign_files USING btree (file_id);


--
-- Name: idx_campaign_seed_companies_campaign_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_campaign_seed_companies_campaign_id ON public.campaign_seed_companies USING btree (campaign_id);


--
-- Name: idx_campaign_seed_companies_is_active; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_campaign_seed_companies_is_active ON public.campaign_seed_companies USING btree (campaign_id, is_active) WHERE (is_active = true);


--
-- Name: idx_campaign_seed_companies_organization_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_campaign_seed_companies_organization_id ON public.campaign_seed_companies USING btree (organization_id);


--
-- Name: idx_campaign_seed_companies_processing_order; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_campaign_seed_companies_processing_order ON public.campaign_seed_companies USING btree (campaign_id, processing_order);


--
-- Name: idx_campaigns_autopilot_enabled; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_campaigns_autopilot_enabled ON public.campaigns USING btree (autopilot_enabled) WHERE (autopilot_enabled = true);


--
-- Name: idx_campaigns_created_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_campaigns_created_at ON public.campaigns USING btree (organization_id, created_at DESC);


--
-- Name: idx_campaigns_csv_template_upload; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_campaigns_csv_template_upload ON public.campaigns USING btree (organization_id, csv_template_upload) WHERE (csv_template_upload = true);


--
-- Name: idx_campaigns_current_workflow_node_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_campaigns_current_workflow_node_id ON public.campaigns USING btree (current_workflow_node_id) WHERE (current_workflow_node_id IS NOT NULL);


--
-- Name: idx_campaigns_deep_research_override; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_campaigns_deep_research_override ON public.campaigns USING btree (deep_research_override) WHERE (deep_research_override = true);


--
-- Name: idx_campaigns_deep_research_provider; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_campaigns_deep_research_provider ON public.campaigns USING btree (deep_research_provider) WHERE (deep_research_provider IS NOT NULL);


--
-- Name: idx_campaigns_icp_profile_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_campaigns_icp_profile_id ON public.campaigns USING btree (icp_profile_id) WHERE (icp_profile_id IS NOT NULL);


--
-- Name: idx_campaigns_language; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_campaigns_language ON public.campaigns USING btree (language);


--
-- Name: idx_campaigns_lookalike_total_found; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_campaigns_lookalike_total_found ON public.campaigns USING btree (lookalike_total_found);


--
-- Name: idx_campaigns_lookalike_total_processed; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_campaigns_lookalike_total_processed ON public.campaigns USING btree (lookalike_total_processed);


--
-- Name: idx_campaigns_org_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_campaigns_org_id ON public.campaigns USING btree (organization_id);


--
-- Name: idx_campaigns_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_campaigns_status ON public.campaigns USING btree (organization_id, status);


--
-- Name: idx_campaigns_user_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_campaigns_user_id ON public.campaigns USING btree (user_id);


--
-- Name: idx_companies_blocked_by_icp; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_companies_blocked_by_icp ON public.companies USING btree (blocked_by_icp) WHERE (blocked_by_icp = true);


--
-- Name: idx_companies_blocked_icp; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_companies_blocked_icp ON public.companies USING btree (blocked_by_icp) WHERE (blocked_by_icp = true);


--
-- Name: idx_companies_contact_extraction_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_companies_contact_extraction_status ON public.companies USING btree (contact_extraction_status) WHERE (contact_extraction_status IS NOT NULL);


--
-- Name: idx_companies_deep_research_v2; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_companies_deep_research_v2 ON public.companies USING gin (deep_research_v2);


--
-- Name: idx_companies_failed_reason; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_companies_failed_reason ON public.companies USING btree (organization_id, processing_status, failure_reason) WHERE (processing_status = 'failed'::text);


--
-- Name: idx_companies_industries; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_companies_industries ON public.companies USING gin (industries);


--
-- Name: idx_companies_linkedin_url; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_companies_linkedin_url ON public.companies USING btree (linkedin_url) WHERE (linkedin_url IS NOT NULL);


--
-- Name: idx_companies_name_trgm; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_companies_name_trgm ON public.companies USING gin (name public.gin_trgm_ops);


--
-- Name: idx_companies_org_blocked; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_companies_org_blocked ON public.companies USING btree (organization_id, blocked_by_icp);


--
-- Name: idx_companies_org_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_companies_org_id ON public.companies USING btree (organization_id);


--
-- Name: idx_companies_org_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_companies_org_status ON public.companies USING btree (organization_id, processing_status);


--
-- Name: idx_companies_processing_log; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_companies_processing_log ON public.companies USING gin (processing_log);


--
-- Name: idx_companies_processing_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_companies_processing_status ON public.companies USING btree (processing_status) WHERE (processing_status = ANY (ARRAY['pending'::text, 'processing'::text]));


--
-- Name: idx_companies_sales_brief; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_companies_sales_brief ON public.companies USING gin (sales_brief) WHERE (sales_brief IS NOT NULL);


--
-- Name: idx_companies_used_for_outreach; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_companies_used_for_outreach ON public.companies USING btree (organization_id, used_for_outreach) WHERE (used_for_outreach = true);


--
-- Name: idx_companies_website; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_companies_website ON public.companies USING btree (website) WHERE (website IS NOT NULL);


--
-- Name: idx_company_activities_company_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_company_activities_company_id ON public.company_activities USING btree (company_id);


--
-- Name: idx_company_activities_created_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_company_activities_created_at ON public.company_activities USING btree (company_id, created_at DESC);


--
-- Name: idx_company_activities_org_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_company_activities_org_id ON public.company_activities USING btree (organization_id);


--
-- Name: idx_company_contacts_company_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_company_contacts_company_id ON public.company_contacts USING btree (company_id);


--
-- Name: idx_company_contacts_contact_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_company_contacts_contact_id ON public.company_contacts USING btree (contact_id);


--
-- Name: idx_company_contacts_org_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_company_contacts_org_id ON public.company_contacts USING btree (organization_id);


--
-- Name: idx_company_research_jobs_campaign_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_company_research_jobs_campaign_id ON public.company_research_jobs USING btree (campaign_id);


--
-- Name: idx_company_research_jobs_company_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_company_research_jobs_company_id ON public.company_research_jobs USING btree (company_id);


--
-- Name: idx_company_research_jobs_created_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_company_research_jobs_created_at ON public.company_research_jobs USING btree (created_at);


--
-- Name: idx_company_research_jobs_organization_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_company_research_jobs_organization_id ON public.company_research_jobs USING btree (organization_id);


--
-- Name: idx_company_research_jobs_research_result_gin; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_company_research_jobs_research_result_gin ON public.company_research_jobs USING gin (research_result);


--
-- Name: idx_company_research_jobs_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_company_research_jobs_status ON public.company_research_jobs USING btree (status);


--
-- Name: idx_company_research_jobs_steps_gin; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_company_research_jobs_steps_gin ON public.company_research_jobs USING gin (steps);


--
-- Name: idx_contact_activities_contact_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_contact_activities_contact_id ON public.contact_activities USING btree (contact_id);


--
-- Name: idx_contact_activities_occurred_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_contact_activities_occurred_at ON public.contact_activities USING btree (contact_id, occurred_at DESC);


--
-- Name: idx_contact_activities_org_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_contact_activities_org_id ON public.contact_activities USING btree (organization_id);


--
-- Name: idx_contact_channels_contact_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_contact_channels_contact_id ON public.contact_channels USING btree (contact_id);


--
-- Name: idx_contact_channels_org_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_contact_channels_org_id ON public.contact_channels USING btree (organization_id);


--
-- Name: idx_contact_channels_primary; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_contact_channels_primary ON public.contact_channels USING btree (contact_id, is_primary) WHERE (is_primary = true);


--
-- Name: idx_contacts_b2b_email_requested; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_contacts_b2b_email_requested ON public.contacts USING btree (organization_id, b2b_email_requested) WHERE (b2b_email_requested = false);


--
-- Name: idx_contacts_do_not_contact; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_contacts_do_not_contact ON public.contacts USING btree (do_not_contact) WHERE (do_not_contact = true);


--
-- Name: idx_contacts_email; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_contacts_email ON public.contacts USING btree (email) WHERE (email IS NOT NULL);


--
-- Name: idx_contacts_email_search_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_contacts_email_search_status ON public.contacts USING btree (email_search_status);


--
-- Name: idx_contacts_hunter_email_requested; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_contacts_hunter_email_requested ON public.contacts USING btree (organization_id, hunter_email_requested) WHERE (hunter_email_requested = false);


--
-- Name: idx_contacts_hunter_email_response; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_contacts_hunter_email_response ON public.contacts USING gin (hunter_email_response);


--
-- Name: idx_contacts_icypeas_email_requested; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_contacts_icypeas_email_requested ON public.contacts USING btree (organization_id, icypeas_email_requested) WHERE (icypeas_email_requested = false);


--
-- Name: idx_contacts_icypeas_email_response; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_contacts_icypeas_email_response ON public.contacts USING gin (icypeas_email_response);


--
-- Name: idx_contacts_location; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_contacts_location ON public.contacts USING btree (location);


--
-- Name: idx_contacts_name_trgm; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_contacts_name_trgm ON public.contacts USING gin (name public.gin_trgm_ops);


--
-- Name: idx_contacts_org_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_contacts_org_id ON public.contacts USING btree (organization_id);


--
-- Name: idx_contacts_organization_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_contacts_organization_id ON public.contacts USING btree (organization_id);


--
-- Name: idx_contacts_pipeline_stage; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_contacts_pipeline_stage ON public.contacts USING btree (organization_id, pipeline_stage) WHERE (pipeline_stage IS NOT NULL);


--
-- Name: idx_contacts_processing_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_contacts_processing_status ON public.contacts USING btree (processing_status) WHERE (processing_status = ANY (ARRAY['pending'::text, 'processing'::text]));


--
-- Name: idx_contacts_provider_responses; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_contacts_provider_responses ON public.contacts USING gin (provider_responses);


--
-- Name: idx_contacts_sales_brief; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_contacts_sales_brief ON public.contacts USING gin (sales_brief) WHERE (sales_brief IS NOT NULL);


--
-- Name: idx_contacts_stop_drafts; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_contacts_stop_drafts ON public.contacts USING btree (organization_id) WHERE (stop_drafts = true);


--
-- Name: idx_contacts_unsubscribed; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_contacts_unsubscribed ON public.contacts USING btree (organization_id) WHERE (unsubscribed_at IS NOT NULL);


--
-- Name: idx_conversation_messages_conversation_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_conversation_messages_conversation_id ON public.conversation_messages USING btree (conversation_id);


--
-- Name: idx_conversation_messages_email_message_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_conversation_messages_email_message_id ON public.conversation_messages USING btree (email_message_id) WHERE (email_message_id IS NOT NULL);


--
-- Name: idx_conversation_messages_org_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_conversation_messages_org_id ON public.conversation_messages USING btree (organization_id);


--
-- Name: idx_conversations_contact_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_conversations_contact_id ON public.conversations USING btree (contact_id);


--
-- Name: idx_conversations_last_message_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_conversations_last_message_at ON public.conversations USING btree (organization_id, last_message_at DESC);


--
-- Name: idx_conversations_org_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_conversations_org_id ON public.conversations USING btree (organization_id);


--
-- Name: idx_conversations_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_conversations_status ON public.conversations USING btree (organization_id, status) WHERE (status <> 'closed'::text);


--
-- Name: idx_conversations_unread; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_conversations_unread ON public.conversations USING btree (organization_id, is_unread) WHERE (is_unread = true);


--
-- Name: idx_conversations_user_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_conversations_user_id ON public.conversations USING btree (user_id) WHERE (user_id IS NOT NULL);


--
-- Name: idx_deep_research_settings_org_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_deep_research_settings_org_id ON public.deep_research_settings USING btree (organization_id);


--
-- Name: idx_feedback_interview_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_feedback_interview_id ON public.feedback USING btree (interview_id);


--
-- Name: idx_icp_profiles_created_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_icp_profiles_created_at ON public.icp_profiles USING btree (created_at DESC);


--
-- Name: idx_icp_profiles_organization_default; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_icp_profiles_organization_default ON public.icp_profiles USING btree (organization_id, is_default) WHERE (is_default = true);


--
-- Name: idx_icp_profiles_organization_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_icp_profiles_organization_id ON public.icp_profiles USING btree (organization_id);


--
-- Name: idx_interview_org_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_interview_org_id ON public.interview USING btree (organization_id);


--
-- Name: idx_interview_user_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_interview_user_id ON public.interview USING btree (user_id) WHERE (user_id IS NOT NULL);


--
-- Name: idx_organization_deleted; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_organization_deleted ON public.organization USING btree (deleted);


--
-- Name: idx_organization_files_category; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_organization_files_category ON public.organization_files USING btree (organization_id, file_category);


--
-- Name: idx_organization_files_chunks_file_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_organization_files_chunks_file_id ON public.organization_files_chunks USING btree (file_id);


--
-- Name: idx_organization_files_chunks_org_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_organization_files_chunks_org_id ON public.organization_files_chunks USING btree (organization_id);


--
-- Name: idx_organization_files_has_sensitive_data; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_organization_files_has_sensitive_data ON public.organization_files USING btree (organization_id, has_sensitive_data) WHERE (has_sensitive_data = true);


--
-- Name: idx_organization_files_hash; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_organization_files_hash ON public.organization_files USING btree (organization_id, file_hash) WHERE (file_hash IS NOT NULL);


--
-- Name: idx_organization_files_industries; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_organization_files_industries ON public.organization_files USING gin (industries) WHERE (file_category = 'case_study'::public.file_category_enum);


--
-- Name: idx_organization_files_org_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_organization_files_org_id ON public.organization_files USING btree (organization_id);


--
-- Name: idx_organization_files_processing_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_organization_files_processing_status ON public.organization_files USING btree (processing_status);


--
-- Name: idx_organization_files_uploaded_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_organization_files_uploaded_at ON public.organization_files USING btree (organization_id, uploaded_at DESC);


--
-- Name: idx_organization_settings_api_key; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_organization_settings_api_key ON public.organization_settings USING btree (api_key) WHERE (api_key IS NOT NULL);


--
-- Name: idx_organization_settings_org_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_organization_settings_org_id ON public.organization_settings USING btree (organization_id);


--
-- Name: idx_response_interview_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_response_interview_id ON public.response USING btree (interview_id);


--
-- Name: idx_response_org_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_response_org_id ON public.response USING btree (organization_id);


--
-- Name: idx_short_urls_contact; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_short_urls_contact ON public.document_short_urls USING btree (contact_id);


--
-- Name: idx_short_urls_expires_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_short_urls_expires_at ON public.document_short_urls USING btree (expires_at);


--
-- Name: idx_short_urls_file_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_short_urls_file_id ON public.document_short_urls USING btree (file_id);


--
-- Name: idx_short_urls_organization; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_short_urls_organization ON public.document_short_urls USING btree (organization_id);


--
-- Name: idx_short_urls_short_code; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_short_urls_short_code ON public.document_short_urls USING btree (short_code);


--
-- Name: idx_tasks_campaign_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_tasks_campaign_id ON public.tasks USING btree (campaign_id) WHERE (campaign_id IS NOT NULL);


--
-- Name: idx_tasks_company_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_tasks_company_id ON public.tasks USING btree (company_id) WHERE (company_id IS NOT NULL);


--
-- Name: idx_tasks_contact_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_tasks_contact_id ON public.tasks USING btree (contact_id) WHERE (contact_id IS NOT NULL);


--
-- Name: idx_tasks_conversation_summary_text_search; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_tasks_conversation_summary_text_search ON public.tasks USING gin (to_tsvector('english'::regconfig, conversation_summary_text));


--
-- Name: idx_tasks_conversation_summary_thread_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_tasks_conversation_summary_thread_id ON public.tasks USING gin (((conversation_summary -> 'thread_id'::text)));


--
-- Name: idx_tasks_created_by; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_tasks_created_by ON public.tasks USING btree (created_by_user_id);


--
-- Name: idx_tasks_feedback; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_tasks_feedback ON public.tasks USING btree (feedback) WHERE (feedback IS NOT NULL);


--
-- Name: idx_tasks_generation_log; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_tasks_generation_log ON public.tasks USING gin (generation_log);


--
-- Name: idx_tasks_org_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_tasks_org_id ON public.tasks USING btree (organization_id);


--
-- Name: idx_tasks_priority_rank; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_tasks_priority_rank ON public.tasks USING btree (priority_rank);


--
-- Name: idx_tasks_scheduled; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_tasks_scheduled ON public.tasks USING btree (organization_id, scheduled) WHERE (scheduled = true);


--
-- Name: idx_tasks_send_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_tasks_send_status ON public.tasks USING btree (organization_id, send_status) WHERE (send_status IS NOT NULL);


--
-- Name: idx_tasks_send_status_failed; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_tasks_send_status_failed ON public.tasks USING btree (organization_id, send_status, updated_at) WHERE (send_status = 'sent_failed'::text);


--
-- Name: idx_tasks_sent_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_tasks_sent_at ON public.tasks USING btree (organization_id, sent_at) WHERE (sent_at IS NOT NULL);


--
-- Name: idx_tasks_subject; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_tasks_subject ON public.tasks USING btree (organization_id, subject) WHERE (subject IS NOT NULL);


--
-- Name: idx_tasks_unanswered_questions; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_tasks_unanswered_questions ON public.tasks USING gin (((conversation_summary -> 'unanswered_questions'::text)));


--
-- Name: idx_token_usage_org_session; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_token_usage_org_session ON public.token_usage USING btree (organization_id, session_id);


--
-- Name: idx_token_usage_tracking_start; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_token_usage_tracking_start ON public.token_usage USING btree (tracking_start DESC);


--
-- Name: idx_usage_campaign_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_usage_campaign_id ON public.usage USING btree (campaign_id);


--
-- Name: idx_usage_context; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_usage_context ON public.usage USING btree (organization_id, usage_context, created_at DESC);


--
-- Name: idx_usage_cost; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_usage_cost ON public.usage USING btree (organization_id, original_cost, sellton_cost);


--
-- Name: idx_usage_created_at_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_usage_created_at_date ON public.usage USING btree (organization_id, date((created_at AT TIME ZONE 'UTC'::text)));


--
-- Name: idx_usage_org_campaign; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_usage_org_campaign ON public.usage USING btree (organization_id, campaign_id) WHERE (campaign_id IS NOT NULL);


--
-- Name: idx_usage_org_costs; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_usage_org_costs ON public.usage USING btree (organization_id, sellton_cost, original_cost) WHERE ((sellton_cost > (0)::numeric) OR (original_cost > (0)::numeric));


--
-- Name: idx_usage_org_created; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_usage_org_created ON public.usage USING btree (organization_id, created_at);


--
-- Name: idx_usage_org_created_desc; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_usage_org_created_desc ON public.usage USING btree (organization_id, created_at DESC);


--
-- Name: idx_usage_org_session; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_usage_org_session ON public.usage USING btree (organization_id, session_id);


--
-- Name: idx_usage_pricing; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_usage_pricing ON public.usage USING gin (original_pricing, sellton_pricing);


--
-- Name: idx_usage_summary_org_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_usage_summary_org_date ON public.usage_summary USING btree (organization_id, date DESC);


--
-- Name: ix_realtime_subscription_entity; Type: INDEX; Schema: realtime; Owner: supabase_admin
--

CREATE INDEX ix_realtime_subscription_entity ON realtime.subscription USING btree (entity);


--
-- Name: messages_inserted_at_topic_index; Type: INDEX; Schema: realtime; Owner: supabase_realtime_admin
--

CREATE INDEX messages_inserted_at_topic_index ON ONLY realtime.messages USING btree (inserted_at DESC, topic) WHERE ((extension = 'broadcast'::text) AND (private IS TRUE));


--
-- Name: messages_2026_02_13_inserted_at_topic_idx; Type: INDEX; Schema: realtime; Owner: supabase_admin
--

CREATE INDEX messages_2026_02_13_inserted_at_topic_idx ON realtime.messages_2026_02_13 USING btree (inserted_at DESC, topic) WHERE ((extension = 'broadcast'::text) AND (private IS TRUE));


--
-- Name: messages_2026_02_14_inserted_at_topic_idx; Type: INDEX; Schema: realtime; Owner: supabase_admin
--

CREATE INDEX messages_2026_02_14_inserted_at_topic_idx ON realtime.messages_2026_02_14 USING btree (inserted_at DESC, topic) WHERE ((extension = 'broadcast'::text) AND (private IS TRUE));


--
-- Name: messages_2026_02_15_inserted_at_topic_idx; Type: INDEX; Schema: realtime; Owner: supabase_admin
--

CREATE INDEX messages_2026_02_15_inserted_at_topic_idx ON realtime.messages_2026_02_15 USING btree (inserted_at DESC, topic) WHERE ((extension = 'broadcast'::text) AND (private IS TRUE));


--
-- Name: messages_2026_02_16_inserted_at_topic_idx; Type: INDEX; Schema: realtime; Owner: supabase_admin
--

CREATE INDEX messages_2026_02_16_inserted_at_topic_idx ON realtime.messages_2026_02_16 USING btree (inserted_at DESC, topic) WHERE ((extension = 'broadcast'::text) AND (private IS TRUE));


--
-- Name: messages_2026_02_17_inserted_at_topic_idx; Type: INDEX; Schema: realtime; Owner: supabase_admin
--

CREATE INDEX messages_2026_02_17_inserted_at_topic_idx ON realtime.messages_2026_02_17 USING btree (inserted_at DESC, topic) WHERE ((extension = 'broadcast'::text) AND (private IS TRUE));


--
-- Name: messages_2026_02_18_inserted_at_topic_idx; Type: INDEX; Schema: realtime; Owner: supabase_admin
--

CREATE INDEX messages_2026_02_18_inserted_at_topic_idx ON realtime.messages_2026_02_18 USING btree (inserted_at DESC, topic) WHERE ((extension = 'broadcast'::text) AND (private IS TRUE));


--
-- Name: messages_2026_02_19_inserted_at_topic_idx; Type: INDEX; Schema: realtime; Owner: supabase_admin
--

CREATE INDEX messages_2026_02_19_inserted_at_topic_idx ON realtime.messages_2026_02_19 USING btree (inserted_at DESC, topic) WHERE ((extension = 'broadcast'::text) AND (private IS TRUE));


--
-- Name: subscription_subscription_id_entity_filters_action_filter_key; Type: INDEX; Schema: realtime; Owner: supabase_admin
--

CREATE UNIQUE INDEX subscription_subscription_id_entity_filters_action_filter_key ON realtime.subscription USING btree (subscription_id, entity, filters, action_filter);


--
-- Name: bname; Type: INDEX; Schema: storage; Owner: supabase_storage_admin
--

CREATE UNIQUE INDEX bname ON storage.buckets USING btree (name);


--
-- Name: bucketid_objname; Type: INDEX; Schema: storage; Owner: supabase_storage_admin
--

CREATE UNIQUE INDEX bucketid_objname ON storage.objects USING btree (bucket_id, name);


--
-- Name: buckets_analytics_unique_name_idx; Type: INDEX; Schema: storage; Owner: supabase_storage_admin
--

CREATE UNIQUE INDEX buckets_analytics_unique_name_idx ON storage.buckets_analytics USING btree (name) WHERE (deleted_at IS NULL);


--
-- Name: idx_multipart_uploads_list; Type: INDEX; Schema: storage; Owner: supabase_storage_admin
--

CREATE INDEX idx_multipart_uploads_list ON storage.s3_multipart_uploads USING btree (bucket_id, key, created_at);


--
-- Name: idx_objects_bucket_id_name; Type: INDEX; Schema: storage; Owner: supabase_storage_admin
--

CREATE INDEX idx_objects_bucket_id_name ON storage.objects USING btree (bucket_id, name COLLATE "C");


--
-- Name: idx_objects_bucket_id_name_lower; Type: INDEX; Schema: storage; Owner: supabase_storage_admin
--

CREATE INDEX idx_objects_bucket_id_name_lower ON storage.objects USING btree (bucket_id, lower(name) COLLATE "C");


--
-- Name: name_prefix_search; Type: INDEX; Schema: storage; Owner: supabase_storage_admin
--

CREATE INDEX name_prefix_search ON storage.objects USING btree (name text_pattern_ops);


--
-- Name: vector_indexes_name_bucket_id_idx; Type: INDEX; Schema: storage; Owner: supabase_storage_admin
--

CREATE UNIQUE INDEX vector_indexes_name_bucket_id_idx ON storage.vector_indexes USING btree (name, bucket_id);


--
-- Name: messages_2026_02_13_inserted_at_topic_idx; Type: INDEX ATTACH; Schema: realtime; Owner: supabase_realtime_admin
--

ALTER INDEX realtime.messages_inserted_at_topic_index ATTACH PARTITION realtime.messages_2026_02_13_inserted_at_topic_idx;


--
-- Name: messages_2026_02_13_pkey; Type: INDEX ATTACH; Schema: realtime; Owner: supabase_realtime_admin
--

ALTER INDEX realtime.messages_pkey ATTACH PARTITION realtime.messages_2026_02_13_pkey;


--
-- Name: messages_2026_02_14_inserted_at_topic_idx; Type: INDEX ATTACH; Schema: realtime; Owner: supabase_realtime_admin
--

ALTER INDEX realtime.messages_inserted_at_topic_index ATTACH PARTITION realtime.messages_2026_02_14_inserted_at_topic_idx;


--
-- Name: messages_2026_02_14_pkey; Type: INDEX ATTACH; Schema: realtime; Owner: supabase_realtime_admin
--

ALTER INDEX realtime.messages_pkey ATTACH PARTITION realtime.messages_2026_02_14_pkey;


--
-- Name: messages_2026_02_15_inserted_at_topic_idx; Type: INDEX ATTACH; Schema: realtime; Owner: supabase_realtime_admin
--

ALTER INDEX realtime.messages_inserted_at_topic_index ATTACH PARTITION realtime.messages_2026_02_15_inserted_at_topic_idx;


--
-- Name: messages_2026_02_15_pkey; Type: INDEX ATTACH; Schema: realtime; Owner: supabase_realtime_admin
--

ALTER INDEX realtime.messages_pkey ATTACH PARTITION realtime.messages_2026_02_15_pkey;


--
-- Name: messages_2026_02_16_inserted_at_topic_idx; Type: INDEX ATTACH; Schema: realtime; Owner: supabase_realtime_admin
--

ALTER INDEX realtime.messages_inserted_at_topic_index ATTACH PARTITION realtime.messages_2026_02_16_inserted_at_topic_idx;


--
-- Name: messages_2026_02_16_pkey; Type: INDEX ATTACH; Schema: realtime; Owner: supabase_realtime_admin
--

ALTER INDEX realtime.messages_pkey ATTACH PARTITION realtime.messages_2026_02_16_pkey;


--
-- Name: messages_2026_02_17_inserted_at_topic_idx; Type: INDEX ATTACH; Schema: realtime; Owner: supabase_realtime_admin
--

ALTER INDEX realtime.messages_inserted_at_topic_index ATTACH PARTITION realtime.messages_2026_02_17_inserted_at_topic_idx;


--
-- Name: messages_2026_02_17_pkey; Type: INDEX ATTACH; Schema: realtime; Owner: supabase_realtime_admin
--

ALTER INDEX realtime.messages_pkey ATTACH PARTITION realtime.messages_2026_02_17_pkey;


--
-- Name: messages_2026_02_18_inserted_at_topic_idx; Type: INDEX ATTACH; Schema: realtime; Owner: supabase_realtime_admin
--

ALTER INDEX realtime.messages_inserted_at_topic_index ATTACH PARTITION realtime.messages_2026_02_18_inserted_at_topic_idx;


--
-- Name: messages_2026_02_18_pkey; Type: INDEX ATTACH; Schema: realtime; Owner: supabase_realtime_admin
--

ALTER INDEX realtime.messages_pkey ATTACH PARTITION realtime.messages_2026_02_18_pkey;


--
-- Name: messages_2026_02_19_inserted_at_topic_idx; Type: INDEX ATTACH; Schema: realtime; Owner: supabase_realtime_admin
--

ALTER INDEX realtime.messages_inserted_at_topic_index ATTACH PARTITION realtime.messages_2026_02_19_inserted_at_topic_idx;


--
-- Name: messages_2026_02_19_pkey; Type: INDEX ATTACH; Schema: realtime; Owner: supabase_realtime_admin
--

ALTER INDEX realtime.messages_pkey ATTACH PARTITION realtime.messages_2026_02_19_pkey;


--
-- Name: tasks trigger_set_task_priority_rank; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_set_task_priority_rank BEFORE INSERT OR UPDATE OF priority ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.set_task_priority_rank();


--
-- Name: companies update_company_blocked_status_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_company_blocked_status_trigger BEFORE INSERT OR UPDATE OF icp_score ON public.companies FOR EACH ROW EXECUTE FUNCTION public.update_company_blocked_status();


--
-- Name: TRIGGER update_company_blocked_status_trigger ON companies; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TRIGGER update_company_blocked_status_trigger ON public.companies IS 'Automatically sets blocked_by_icp based on icp_score.blocked flag';


--
-- Name: icp_profiles update_icp_profiles_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_icp_profiles_updated_at BEFORE UPDATE ON public.icp_profiles FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: subscription tr_check_filters; Type: TRIGGER; Schema: realtime; Owner: supabase_admin
--

CREATE TRIGGER tr_check_filters BEFORE INSERT OR UPDATE ON realtime.subscription FOR EACH ROW EXECUTE FUNCTION realtime.subscription_check_filters();


--
-- Name: buckets enforce_bucket_name_length_trigger; Type: TRIGGER; Schema: storage; Owner: supabase_storage_admin
--

CREATE TRIGGER enforce_bucket_name_length_trigger BEFORE INSERT OR UPDATE OF name ON storage.buckets FOR EACH ROW EXECUTE FUNCTION storage.enforce_bucket_name_length();


--
-- Name: buckets protect_buckets_delete; Type: TRIGGER; Schema: storage; Owner: supabase_storage_admin
--

CREATE TRIGGER protect_buckets_delete BEFORE DELETE ON storage.buckets FOR EACH STATEMENT EXECUTE FUNCTION storage.protect_delete();


--
-- Name: objects protect_objects_delete; Type: TRIGGER; Schema: storage; Owner: supabase_storage_admin
--

CREATE TRIGGER protect_objects_delete BEFORE DELETE ON storage.objects FOR EACH STATEMENT EXECUTE FUNCTION storage.protect_delete();


--
-- Name: objects update_objects_updated_at; Type: TRIGGER; Schema: storage; Owner: supabase_storage_admin
--

CREATE TRIGGER update_objects_updated_at BEFORE UPDATE ON storage.objects FOR EACH ROW EXECUTE FUNCTION storage.update_updated_at_column();


--
-- Name: identities identities_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.identities
    ADD CONSTRAINT identities_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: mfa_amr_claims mfa_amr_claims_session_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.mfa_amr_claims
    ADD CONSTRAINT mfa_amr_claims_session_id_fkey FOREIGN KEY (session_id) REFERENCES auth.sessions(id) ON DELETE CASCADE;


--
-- Name: mfa_challenges mfa_challenges_auth_factor_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.mfa_challenges
    ADD CONSTRAINT mfa_challenges_auth_factor_id_fkey FOREIGN KEY (factor_id) REFERENCES auth.mfa_factors(id) ON DELETE CASCADE;


--
-- Name: mfa_factors mfa_factors_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.mfa_factors
    ADD CONSTRAINT mfa_factors_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: oauth_authorizations oauth_authorizations_client_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.oauth_authorizations
    ADD CONSTRAINT oauth_authorizations_client_id_fkey FOREIGN KEY (client_id) REFERENCES auth.oauth_clients(id) ON DELETE CASCADE;


--
-- Name: oauth_authorizations oauth_authorizations_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.oauth_authorizations
    ADD CONSTRAINT oauth_authorizations_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: oauth_consents oauth_consents_client_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.oauth_consents
    ADD CONSTRAINT oauth_consents_client_id_fkey FOREIGN KEY (client_id) REFERENCES auth.oauth_clients(id) ON DELETE CASCADE;


--
-- Name: oauth_consents oauth_consents_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.oauth_consents
    ADD CONSTRAINT oauth_consents_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: one_time_tokens one_time_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.one_time_tokens
    ADD CONSTRAINT one_time_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: refresh_tokens refresh_tokens_session_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.refresh_tokens
    ADD CONSTRAINT refresh_tokens_session_id_fkey FOREIGN KEY (session_id) REFERENCES auth.sessions(id) ON DELETE CASCADE;


--
-- Name: saml_providers saml_providers_sso_provider_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.saml_providers
    ADD CONSTRAINT saml_providers_sso_provider_id_fkey FOREIGN KEY (sso_provider_id) REFERENCES auth.sso_providers(id) ON DELETE CASCADE;


--
-- Name: saml_relay_states saml_relay_states_flow_state_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.saml_relay_states
    ADD CONSTRAINT saml_relay_states_flow_state_id_fkey FOREIGN KEY (flow_state_id) REFERENCES auth.flow_state(id) ON DELETE CASCADE;


--
-- Name: saml_relay_states saml_relay_states_sso_provider_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.saml_relay_states
    ADD CONSTRAINT saml_relay_states_sso_provider_id_fkey FOREIGN KEY (sso_provider_id) REFERENCES auth.sso_providers(id) ON DELETE CASCADE;


--
-- Name: sessions sessions_oauth_client_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.sessions
    ADD CONSTRAINT sessions_oauth_client_id_fkey FOREIGN KEY (oauth_client_id) REFERENCES auth.oauth_clients(id) ON DELETE CASCADE;


--
-- Name: sessions sessions_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.sessions
    ADD CONSTRAINT sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: sso_domains sso_domains_sso_provider_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.sso_domains
    ADD CONSTRAINT sso_domains_sso_provider_id_fkey FOREIGN KEY (sso_provider_id) REFERENCES auth.sso_providers(id) ON DELETE CASCADE;


--
-- Name: campaign_activities campaign_activities_campaign_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.campaign_activities
    ADD CONSTRAINT campaign_activities_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES public.campaigns(id) ON DELETE CASCADE;


--
-- Name: campaign_activities campaign_activities_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.campaign_activities
    ADD CONSTRAINT campaign_activities_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: campaign_activities campaign_activities_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.campaign_activities
    ADD CONSTRAINT campaign_activities_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON DELETE CASCADE;


--
-- Name: campaign_companies campaign_companies_campaign_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.campaign_companies
    ADD CONSTRAINT campaign_companies_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES public.campaigns(id) ON DELETE CASCADE;


--
-- Name: campaign_companies campaign_companies_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.campaign_companies
    ADD CONSTRAINT campaign_companies_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- Name: campaign_companies campaign_companies_icp_profile_id_used_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.campaign_companies
    ADD CONSTRAINT campaign_companies_icp_profile_id_used_fkey FOREIGN KEY (icp_profile_id_used) REFERENCES public.icp_profiles(id) ON DELETE SET NULL;


--
-- Name: campaign_companies campaign_companies_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.campaign_companies
    ADD CONSTRAINT campaign_companies_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON DELETE CASCADE;


--
-- Name: campaign_emails campaign_emails_campaign_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.campaign_emails
    ADD CONSTRAINT campaign_emails_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES public.campaigns(id) ON DELETE CASCADE;


--
-- Name: campaign_emails campaign_emails_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.campaign_emails
    ADD CONSTRAINT campaign_emails_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: campaign_emails campaign_emails_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.campaign_emails
    ADD CONSTRAINT campaign_emails_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON DELETE CASCADE;


--
-- Name: campaign_files campaign_files_campaign_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.campaign_files
    ADD CONSTRAINT campaign_files_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES public.campaigns(id) ON DELETE CASCADE;


--
-- Name: campaign_files campaign_files_file_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.campaign_files
    ADD CONSTRAINT campaign_files_file_id_fkey FOREIGN KEY (file_id) REFERENCES public.organization_files(id) ON DELETE CASCADE;


--
-- Name: campaign_seed_companies campaign_seed_companies_campaign_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.campaign_seed_companies
    ADD CONSTRAINT campaign_seed_companies_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES public.campaigns(id) ON DELETE CASCADE;


--
-- Name: campaign_seed_companies campaign_seed_companies_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.campaign_seed_companies
    ADD CONSTRAINT campaign_seed_companies_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON DELETE CASCADE;


--
-- Name: campaigns campaigns_icp_profile_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.campaigns
    ADD CONSTRAINT campaigns_icp_profile_id_fkey FOREIGN KEY (icp_profile_id) REFERENCES public.icp_profiles(id) ON DELETE SET NULL;


--
-- Name: campaigns campaigns_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.campaigns
    ADD CONSTRAINT campaigns_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON DELETE CASCADE;


--
-- Name: companies companies_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.companies
    ADD CONSTRAINT companies_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON DELETE CASCADE;


--
-- Name: company_activities company_activities_campaign_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_activities
    ADD CONSTRAINT company_activities_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES public.campaigns(id) ON DELETE SET NULL;


--
-- Name: company_activities company_activities_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_activities
    ADD CONSTRAINT company_activities_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- Name: company_activities company_activities_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_activities
    ADD CONSTRAINT company_activities_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE SET NULL;


--
-- Name: company_activities company_activities_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_activities
    ADD CONSTRAINT company_activities_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON DELETE CASCADE;


--
-- Name: company_activities company_activities_task_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_activities
    ADD CONSTRAINT company_activities_task_id_fkey FOREIGN KEY (task_id) REFERENCES public.tasks(id) ON DELETE SET NULL;


--
-- Name: company_contacts company_contacts_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_contacts
    ADD CONSTRAINT company_contacts_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- Name: company_contacts company_contacts_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_contacts
    ADD CONSTRAINT company_contacts_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: company_contacts company_contacts_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_contacts
    ADD CONSTRAINT company_contacts_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON DELETE CASCADE;


--
-- Name: company_research_jobs company_research_jobs_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_research_jobs
    ADD CONSTRAINT company_research_jobs_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- Name: company_research_jobs company_research_jobs_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_research_jobs
    ADD CONSTRAINT company_research_jobs_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON DELETE CASCADE;


--
-- Name: contact_activities contact_activities_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.contact_activities
    ADD CONSTRAINT contact_activities_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: contact_activities contact_activities_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.contact_activities
    ADD CONSTRAINT contact_activities_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON DELETE CASCADE;


--
-- Name: contact_activities contact_activities_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.contact_activities
    ADD CONSTRAINT contact_activities_user_id_fkey FOREIGN KEY (user_id) REFERENCES public."user"(id) ON DELETE SET NULL;


--
-- Name: contact_channels contact_channels_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.contact_channels
    ADD CONSTRAINT contact_channels_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: contact_channels contact_channels_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.contact_channels
    ADD CONSTRAINT contact_channels_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON DELETE CASCADE;


--
-- Name: contact_notes contact_notes_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.contact_notes
    ADD CONSTRAINT contact_notes_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: contact_notes contact_notes_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.contact_notes
    ADD CONSTRAINT contact_notes_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON DELETE CASCADE;


--
-- Name: contact_notes contact_notes_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.contact_notes
    ADD CONSTRAINT contact_notes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public."user"(id) ON DELETE SET NULL;


--
-- Name: contacts contacts_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.contacts
    ADD CONSTRAINT contacts_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON DELETE CASCADE;


--
-- Name: conversation_messages conversation_messages_conversation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.conversation_messages
    ADD CONSTRAINT conversation_messages_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.conversations(id) ON DELETE CASCADE;


--
-- Name: conversation_messages conversation_messages_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.conversation_messages
    ADD CONSTRAINT conversation_messages_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON DELETE CASCADE;


--
-- Name: conversation_messages conversation_messages_sender_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.conversation_messages
    ADD CONSTRAINT conversation_messages_sender_user_id_fkey FOREIGN KEY (sender_user_id) REFERENCES public."user"(id) ON DELETE SET NULL;


--
-- Name: conversations conversations_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: conversations conversations_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON DELETE CASCADE;


--
-- Name: conversations conversations_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_user_id_fkey FOREIGN KEY (user_id) REFERENCES public."user"(id) ON DELETE SET NULL;


--
-- Name: deep_research_settings deep_research_settings_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.deep_research_settings
    ADD CONSTRAINT deep_research_settings_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON DELETE CASCADE;


--
-- Name: feedback feedback_interview_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.feedback
    ADD CONSTRAINT feedback_interview_id_fkey FOREIGN KEY (interview_id) REFERENCES public.interview(id) ON DELETE CASCADE;


--
-- Name: feedback feedback_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.feedback
    ADD CONSTRAINT feedback_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON DELETE CASCADE;


--
-- Name: document_short_urls fk_contact; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.document_short_urls
    ADD CONSTRAINT fk_contact FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE SET NULL;


--
-- Name: document_access_events fk_contact_event; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.document_access_events
    ADD CONSTRAINT fk_contact_event FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE SET NULL;


--
-- Name: document_short_urls fk_organization; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.document_short_urls
    ADD CONSTRAINT fk_organization FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON DELETE CASCADE;


--
-- Name: document_access_events fk_short_url; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.document_access_events
    ADD CONSTRAINT fk_short_url FOREIGN KEY (short_url_id) REFERENCES public.document_short_urls(id) ON DELETE CASCADE;


--
-- Name: icp_profiles icp_profiles_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.icp_profiles
    ADD CONSTRAINT icp_profiles_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON DELETE CASCADE;


--
-- Name: interview interview_interviewer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.interview
    ADD CONSTRAINT interview_interviewer_id_fkey FOREIGN KEY (interviewer_id) REFERENCES public.interviewer(id) ON DELETE SET NULL;


--
-- Name: interview interview_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.interview
    ADD CONSTRAINT interview_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON DELETE CASCADE;


--
-- Name: interview interview_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.interview
    ADD CONSTRAINT interview_user_id_fkey FOREIGN KEY (user_id) REFERENCES public."user"(id) ON DELETE SET NULL;


--
-- Name: interviewer interviewer_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.interviewer
    ADD CONSTRAINT interviewer_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON DELETE CASCADE;


--
-- Name: organization_files_chunks organization_files_chunks_file_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.organization_files_chunks
    ADD CONSTRAINT organization_files_chunks_file_id_fkey FOREIGN KEY (file_id) REFERENCES public.organization_files(id) ON DELETE CASCADE;


--
-- Name: organization_files_chunks organization_files_chunks_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.organization_files_chunks
    ADD CONSTRAINT organization_files_chunks_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON DELETE CASCADE;


--
-- Name: organization_files organization_files_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.organization_files
    ADD CONSTRAINT organization_files_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON DELETE CASCADE;


--
-- Name: organization_icp_linkedin_urls organization_icp_linkedin_urls_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.organization_icp_linkedin_urls
    ADD CONSTRAINT organization_icp_linkedin_urls_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON DELETE CASCADE;


--
-- Name: organization_settings organization_settings_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.organization_settings
    ADD CONSTRAINT organization_settings_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON DELETE CASCADE;


--
-- Name: response response_interview_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.response
    ADD CONSTRAINT response_interview_id_fkey FOREIGN KEY (interview_id) REFERENCES public.interview(id) ON DELETE CASCADE;


--
-- Name: response response_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.response
    ADD CONSTRAINT response_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON DELETE CASCADE;


--
-- Name: style_guidelines style_guidelines_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.style_guidelines
    ADD CONSTRAINT style_guidelines_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON DELETE CASCADE;


--
-- Name: tasks tasks_campaign_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT tasks_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES public.campaigns(id) ON DELETE CASCADE;


--
-- Name: tasks tasks_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT tasks_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- Name: tasks tasks_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT tasks_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: tasks tasks_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT tasks_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON DELETE CASCADE;


--
-- Name: user_organizations user_organizations_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_organizations
    ADD CONSTRAINT user_organizations_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON DELETE CASCADE;


--
-- Name: user_organizations user_organizations_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_organizations
    ADD CONSTRAINT user_organizations_user_id_fkey FOREIGN KEY (user_id) REFERENCES public."user"(id) ON DELETE CASCADE;


--
-- Name: objects objects_bucketId_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE ONLY storage.objects
    ADD CONSTRAINT "objects_bucketId_fkey" FOREIGN KEY (bucket_id) REFERENCES storage.buckets(id);


--
-- Name: s3_multipart_uploads s3_multipart_uploads_bucket_id_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE ONLY storage.s3_multipart_uploads
    ADD CONSTRAINT s3_multipart_uploads_bucket_id_fkey FOREIGN KEY (bucket_id) REFERENCES storage.buckets(id);


--
-- Name: s3_multipart_uploads_parts s3_multipart_uploads_parts_bucket_id_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE ONLY storage.s3_multipart_uploads_parts
    ADD CONSTRAINT s3_multipart_uploads_parts_bucket_id_fkey FOREIGN KEY (bucket_id) REFERENCES storage.buckets(id);


--
-- Name: s3_multipart_uploads_parts s3_multipart_uploads_parts_upload_id_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE ONLY storage.s3_multipart_uploads_parts
    ADD CONSTRAINT s3_multipart_uploads_parts_upload_id_fkey FOREIGN KEY (upload_id) REFERENCES storage.s3_multipart_uploads(id) ON DELETE CASCADE;


--
-- Name: vector_indexes vector_indexes_bucket_id_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE ONLY storage.vector_indexes
    ADD CONSTRAINT vector_indexes_bucket_id_fkey FOREIGN KEY (bucket_id) REFERENCES storage.buckets_vectors(id);


--
-- Name: audit_log_entries; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.audit_log_entries ENABLE ROW LEVEL SECURITY;

--
-- Name: flow_state; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.flow_state ENABLE ROW LEVEL SECURITY;

--
-- Name: identities; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.identities ENABLE ROW LEVEL SECURITY;

--
-- Name: instances; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.instances ENABLE ROW LEVEL SECURITY;

--
-- Name: mfa_amr_claims; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.mfa_amr_claims ENABLE ROW LEVEL SECURITY;

--
-- Name: mfa_challenges; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.mfa_challenges ENABLE ROW LEVEL SECURITY;

--
-- Name: mfa_factors; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.mfa_factors ENABLE ROW LEVEL SECURITY;

--
-- Name: one_time_tokens; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.one_time_tokens ENABLE ROW LEVEL SECURITY;

--
-- Name: refresh_tokens; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.refresh_tokens ENABLE ROW LEVEL SECURITY;

--
-- Name: saml_providers; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.saml_providers ENABLE ROW LEVEL SECURITY;

--
-- Name: saml_relay_states; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.saml_relay_states ENABLE ROW LEVEL SECURITY;

--
-- Name: schema_migrations; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.schema_migrations ENABLE ROW LEVEL SECURITY;

--
-- Name: sessions; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.sessions ENABLE ROW LEVEL SECURITY;

--
-- Name: sso_domains; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.sso_domains ENABLE ROW LEVEL SECURITY;

--
-- Name: sso_providers; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.sso_providers ENABLE ROW LEVEL SECURITY;

--
-- Name: users; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.users ENABLE ROW LEVEL SECURITY;

--
-- Name: document_access_events Service role has full access to access events; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Service role has full access to access events" ON public.document_access_events USING ((auth.role() = 'service_role'::text)) WITH CHECK ((auth.role() = 'service_role'::text));


--
-- Name: document_short_urls Service role has full access to short URLs; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Service role has full access to short URLs" ON public.document_short_urls USING ((auth.role() = 'service_role'::text)) WITH CHECK ((auth.role() = 'service_role'::text));


--
-- Name: campaign_files Users can delete campaign files for their organization; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can delete campaign files for their organization" ON public.campaign_files FOR DELETE USING ((EXISTS ( SELECT 1
   FROM public.campaigns c
  WHERE ((c.id = campaign_files.campaign_id) AND (c.organization_id IN ( SELECT user_organizations.organization_id
           FROM public.user_organizations
          WHERE (user_organizations.user_id = (auth.uid())::text)))))));


--
-- Name: icp_profiles Users can delete their organization's ICP profiles; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can delete their organization's ICP profiles" ON public.icp_profiles FOR DELETE USING ((organization_id IN ( SELECT organization.id
   FROM public.organization
  WHERE (organization.id = icp_profiles.organization_id))));


--
-- Name: icp_profiles Users can insert ICP profiles for their organization; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can insert ICP profiles for their organization" ON public.icp_profiles FOR INSERT WITH CHECK ((organization_id IN ( SELECT organization.id
   FROM public.organization
  WHERE (organization.id = icp_profiles.organization_id))));


--
-- Name: campaign_files Users can insert campaign files for their organization; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can insert campaign files for their organization" ON public.campaign_files FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM public.campaigns c
  WHERE ((c.id = campaign_files.campaign_id) AND (c.organization_id IN ( SELECT user_organizations.organization_id
           FROM public.user_organizations
          WHERE (user_organizations.user_id = (auth.uid())::text)))))));


--
-- Name: icp_profiles Users can update their organization's ICP profiles; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can update their organization's ICP profiles" ON public.icp_profiles FOR UPDATE USING ((organization_id IN ( SELECT organization.id
   FROM public.organization
  WHERE (organization.id = icp_profiles.organization_id))));


--
-- Name: document_access_events Users can view access events for their organization; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can view access events for their organization" ON public.document_access_events FOR SELECT USING ((organization_id IN ( SELECT organization.id
   FROM public.organization
  WHERE (organization.id = document_access_events.organization_id))));


--
-- Name: campaign_files Users can view campaign files for their organization; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can view campaign files for their organization" ON public.campaign_files FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.campaigns c
  WHERE ((c.id = campaign_files.campaign_id) AND (c.organization_id IN ( SELECT user_organizations.organization_id
           FROM public.user_organizations
          WHERE (user_organizations.user_id = (auth.uid())::text)))))));


--
-- Name: document_short_urls Users can view short URLs for their organization; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can view short URLs for their organization" ON public.document_short_urls FOR SELECT USING ((organization_id IN ( SELECT organization.id
   FROM public.organization
  WHERE (organization.id = document_short_urls.organization_id))));


--
-- Name: icp_profiles Users can view their organization's ICP profiles; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can view their organization's ICP profiles" ON public.icp_profiles FOR SELECT USING ((organization_id IN ( SELECT organization.id
   FROM public.organization
  WHERE (organization.id = icp_profiles.organization_id))));


--
-- Name: campaign_files; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.campaign_files ENABLE ROW LEVEL SECURITY;

--
-- Name: document_access_events; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.document_access_events ENABLE ROW LEVEL SECURITY;

--
-- Name: document_short_urls; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.document_short_urls ENABLE ROW LEVEL SECURITY;

--
-- Name: icp_profiles; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.icp_profiles ENABLE ROW LEVEL SECURITY;

--
-- Name: messages; Type: ROW SECURITY; Schema: realtime; Owner: supabase_realtime_admin
--

ALTER TABLE realtime.messages ENABLE ROW LEVEL SECURITY;

--
-- Name: buckets; Type: ROW SECURITY; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE storage.buckets ENABLE ROW LEVEL SECURITY;

--
-- Name: buckets_analytics; Type: ROW SECURITY; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE storage.buckets_analytics ENABLE ROW LEVEL SECURITY;

--
-- Name: buckets_vectors; Type: ROW SECURITY; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE storage.buckets_vectors ENABLE ROW LEVEL SECURITY;

--
-- Name: migrations; Type: ROW SECURITY; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE storage.migrations ENABLE ROW LEVEL SECURITY;

--
-- Name: objects; Type: ROW SECURITY; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

--
-- Name: s3_multipart_uploads; Type: ROW SECURITY; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE storage.s3_multipart_uploads ENABLE ROW LEVEL SECURITY;

--
-- Name: s3_multipart_uploads_parts; Type: ROW SECURITY; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE storage.s3_multipart_uploads_parts ENABLE ROW LEVEL SECURITY;

--
-- Name: vector_indexes; Type: ROW SECURITY; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE storage.vector_indexes ENABLE ROW LEVEL SECURITY;

--
-- Name: supabase_realtime; Type: PUBLICATION; Schema: -; Owner: postgres
--

CREATE PUBLICATION supabase_realtime WITH (publish = 'insert, update, delete, truncate');


ALTER PUBLICATION supabase_realtime OWNER TO postgres;

--
-- Name: supabase_realtime_messages_publication; Type: PUBLICATION; Schema: -; Owner: supabase_admin
--

CREATE PUBLICATION supabase_realtime_messages_publication WITH (publish = 'insert, update, delete, truncate');


ALTER PUBLICATION supabase_realtime_messages_publication OWNER TO supabase_admin;

--
-- Name: supabase_realtime_messages_publication messages; Type: PUBLICATION TABLE; Schema: realtime; Owner: supabase_admin
--

ALTER PUBLICATION supabase_realtime_messages_publication ADD TABLE ONLY realtime.messages;


--
-- Name: SCHEMA auth; Type: ACL; Schema: -; Owner: supabase_admin
--

GRANT USAGE ON SCHEMA auth TO anon;
GRANT USAGE ON SCHEMA auth TO authenticated;
GRANT USAGE ON SCHEMA auth TO service_role;
GRANT ALL ON SCHEMA auth TO supabase_auth_admin;
GRANT ALL ON SCHEMA auth TO dashboard_user;
GRANT USAGE ON SCHEMA auth TO postgres;


--
-- Name: SCHEMA extensions; Type: ACL; Schema: -; Owner: postgres
--

GRANT USAGE ON SCHEMA extensions TO anon;
GRANT USAGE ON SCHEMA extensions TO authenticated;
GRANT USAGE ON SCHEMA extensions TO service_role;
GRANT ALL ON SCHEMA extensions TO dashboard_user;


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: pg_database_owner
--

GRANT USAGE ON SCHEMA public TO postgres;
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;


--
-- Name: SCHEMA realtime; Type: ACL; Schema: -; Owner: supabase_admin
--

GRANT USAGE ON SCHEMA realtime TO postgres;
GRANT USAGE ON SCHEMA realtime TO anon;
GRANT USAGE ON SCHEMA realtime TO authenticated;
GRANT USAGE ON SCHEMA realtime TO service_role;
GRANT ALL ON SCHEMA realtime TO supabase_realtime_admin;


--
-- Name: SCHEMA storage; Type: ACL; Schema: -; Owner: supabase_admin
--

GRANT USAGE ON SCHEMA storage TO postgres WITH GRANT OPTION;
GRANT USAGE ON SCHEMA storage TO anon;
GRANT USAGE ON SCHEMA storage TO authenticated;
GRANT USAGE ON SCHEMA storage TO service_role;
GRANT ALL ON SCHEMA storage TO supabase_storage_admin;
GRANT ALL ON SCHEMA storage TO dashboard_user;


--
-- Name: SCHEMA vault; Type: ACL; Schema: -; Owner: supabase_admin
--

GRANT USAGE ON SCHEMA vault TO postgres WITH GRANT OPTION;
GRANT USAGE ON SCHEMA vault TO service_role;


--
-- Name: FUNCTION gtrgm_in(cstring); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.gtrgm_in(cstring) TO postgres;
GRANT ALL ON FUNCTION public.gtrgm_in(cstring) TO anon;
GRANT ALL ON FUNCTION public.gtrgm_in(cstring) TO authenticated;
GRANT ALL ON FUNCTION public.gtrgm_in(cstring) TO service_role;


--
-- Name: FUNCTION gtrgm_out(public.gtrgm); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.gtrgm_out(public.gtrgm) TO postgres;
GRANT ALL ON FUNCTION public.gtrgm_out(public.gtrgm) TO anon;
GRANT ALL ON FUNCTION public.gtrgm_out(public.gtrgm) TO authenticated;
GRANT ALL ON FUNCTION public.gtrgm_out(public.gtrgm) TO service_role;


--
-- Name: FUNCTION halfvec_in(cstring, oid, integer); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.halfvec_in(cstring, oid, integer) TO postgres;
GRANT ALL ON FUNCTION public.halfvec_in(cstring, oid, integer) TO anon;
GRANT ALL ON FUNCTION public.halfvec_in(cstring, oid, integer) TO authenticated;
GRANT ALL ON FUNCTION public.halfvec_in(cstring, oid, integer) TO service_role;


--
-- Name: FUNCTION halfvec_out(public.halfvec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.halfvec_out(public.halfvec) TO postgres;
GRANT ALL ON FUNCTION public.halfvec_out(public.halfvec) TO anon;
GRANT ALL ON FUNCTION public.halfvec_out(public.halfvec) TO authenticated;
GRANT ALL ON FUNCTION public.halfvec_out(public.halfvec) TO service_role;


--
-- Name: FUNCTION halfvec_recv(internal, oid, integer); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.halfvec_recv(internal, oid, integer) TO postgres;
GRANT ALL ON FUNCTION public.halfvec_recv(internal, oid, integer) TO anon;
GRANT ALL ON FUNCTION public.halfvec_recv(internal, oid, integer) TO authenticated;
GRANT ALL ON FUNCTION public.halfvec_recv(internal, oid, integer) TO service_role;


--
-- Name: FUNCTION halfvec_send(public.halfvec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.halfvec_send(public.halfvec) TO postgres;
GRANT ALL ON FUNCTION public.halfvec_send(public.halfvec) TO anon;
GRANT ALL ON FUNCTION public.halfvec_send(public.halfvec) TO authenticated;
GRANT ALL ON FUNCTION public.halfvec_send(public.halfvec) TO service_role;


--
-- Name: FUNCTION halfvec_typmod_in(cstring[]); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.halfvec_typmod_in(cstring[]) TO postgres;
GRANT ALL ON FUNCTION public.halfvec_typmod_in(cstring[]) TO anon;
GRANT ALL ON FUNCTION public.halfvec_typmod_in(cstring[]) TO authenticated;
GRANT ALL ON FUNCTION public.halfvec_typmod_in(cstring[]) TO service_role;


--
-- Name: FUNCTION sparsevec_in(cstring, oid, integer); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.sparsevec_in(cstring, oid, integer) TO postgres;
GRANT ALL ON FUNCTION public.sparsevec_in(cstring, oid, integer) TO anon;
GRANT ALL ON FUNCTION public.sparsevec_in(cstring, oid, integer) TO authenticated;
GRANT ALL ON FUNCTION public.sparsevec_in(cstring, oid, integer) TO service_role;


--
-- Name: FUNCTION sparsevec_out(public.sparsevec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.sparsevec_out(public.sparsevec) TO postgres;
GRANT ALL ON FUNCTION public.sparsevec_out(public.sparsevec) TO anon;
GRANT ALL ON FUNCTION public.sparsevec_out(public.sparsevec) TO authenticated;
GRANT ALL ON FUNCTION public.sparsevec_out(public.sparsevec) TO service_role;


--
-- Name: FUNCTION sparsevec_recv(internal, oid, integer); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.sparsevec_recv(internal, oid, integer) TO postgres;
GRANT ALL ON FUNCTION public.sparsevec_recv(internal, oid, integer) TO anon;
GRANT ALL ON FUNCTION public.sparsevec_recv(internal, oid, integer) TO authenticated;
GRANT ALL ON FUNCTION public.sparsevec_recv(internal, oid, integer) TO service_role;


--
-- Name: FUNCTION sparsevec_send(public.sparsevec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.sparsevec_send(public.sparsevec) TO postgres;
GRANT ALL ON FUNCTION public.sparsevec_send(public.sparsevec) TO anon;
GRANT ALL ON FUNCTION public.sparsevec_send(public.sparsevec) TO authenticated;
GRANT ALL ON FUNCTION public.sparsevec_send(public.sparsevec) TO service_role;


--
-- Name: FUNCTION sparsevec_typmod_in(cstring[]); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.sparsevec_typmod_in(cstring[]) TO postgres;
GRANT ALL ON FUNCTION public.sparsevec_typmod_in(cstring[]) TO anon;
GRANT ALL ON FUNCTION public.sparsevec_typmod_in(cstring[]) TO authenticated;
GRANT ALL ON FUNCTION public.sparsevec_typmod_in(cstring[]) TO service_role;


--
-- Name: FUNCTION vector_in(cstring, oid, integer); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.vector_in(cstring, oid, integer) TO postgres;
GRANT ALL ON FUNCTION public.vector_in(cstring, oid, integer) TO anon;
GRANT ALL ON FUNCTION public.vector_in(cstring, oid, integer) TO authenticated;
GRANT ALL ON FUNCTION public.vector_in(cstring, oid, integer) TO service_role;


--
-- Name: FUNCTION vector_out(public.vector); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.vector_out(public.vector) TO postgres;
GRANT ALL ON FUNCTION public.vector_out(public.vector) TO anon;
GRANT ALL ON FUNCTION public.vector_out(public.vector) TO authenticated;
GRANT ALL ON FUNCTION public.vector_out(public.vector) TO service_role;


--
-- Name: FUNCTION vector_recv(internal, oid, integer); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.vector_recv(internal, oid, integer) TO postgres;
GRANT ALL ON FUNCTION public.vector_recv(internal, oid, integer) TO anon;
GRANT ALL ON FUNCTION public.vector_recv(internal, oid, integer) TO authenticated;
GRANT ALL ON FUNCTION public.vector_recv(internal, oid, integer) TO service_role;


--
-- Name: FUNCTION vector_send(public.vector); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.vector_send(public.vector) TO postgres;
GRANT ALL ON FUNCTION public.vector_send(public.vector) TO anon;
GRANT ALL ON FUNCTION public.vector_send(public.vector) TO authenticated;
GRANT ALL ON FUNCTION public.vector_send(public.vector) TO service_role;


--
-- Name: FUNCTION vector_typmod_in(cstring[]); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.vector_typmod_in(cstring[]) TO postgres;
GRANT ALL ON FUNCTION public.vector_typmod_in(cstring[]) TO anon;
GRANT ALL ON FUNCTION public.vector_typmod_in(cstring[]) TO authenticated;
GRANT ALL ON FUNCTION public.vector_typmod_in(cstring[]) TO service_role;


--
-- Name: FUNCTION array_to_halfvec(real[], integer, boolean); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.array_to_halfvec(real[], integer, boolean) TO postgres;
GRANT ALL ON FUNCTION public.array_to_halfvec(real[], integer, boolean) TO anon;
GRANT ALL ON FUNCTION public.array_to_halfvec(real[], integer, boolean) TO authenticated;
GRANT ALL ON FUNCTION public.array_to_halfvec(real[], integer, boolean) TO service_role;


--
-- Name: FUNCTION array_to_sparsevec(real[], integer, boolean); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.array_to_sparsevec(real[], integer, boolean) TO postgres;
GRANT ALL ON FUNCTION public.array_to_sparsevec(real[], integer, boolean) TO anon;
GRANT ALL ON FUNCTION public.array_to_sparsevec(real[], integer, boolean) TO authenticated;
GRANT ALL ON FUNCTION public.array_to_sparsevec(real[], integer, boolean) TO service_role;


--
-- Name: FUNCTION array_to_vector(real[], integer, boolean); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.array_to_vector(real[], integer, boolean) TO postgres;
GRANT ALL ON FUNCTION public.array_to_vector(real[], integer, boolean) TO anon;
GRANT ALL ON FUNCTION public.array_to_vector(real[], integer, boolean) TO authenticated;
GRANT ALL ON FUNCTION public.array_to_vector(real[], integer, boolean) TO service_role;


--
-- Name: FUNCTION array_to_halfvec(double precision[], integer, boolean); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.array_to_halfvec(double precision[], integer, boolean) TO postgres;
GRANT ALL ON FUNCTION public.array_to_halfvec(double precision[], integer, boolean) TO anon;
GRANT ALL ON FUNCTION public.array_to_halfvec(double precision[], integer, boolean) TO authenticated;
GRANT ALL ON FUNCTION public.array_to_halfvec(double precision[], integer, boolean) TO service_role;


--
-- Name: FUNCTION array_to_sparsevec(double precision[], integer, boolean); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.array_to_sparsevec(double precision[], integer, boolean) TO postgres;
GRANT ALL ON FUNCTION public.array_to_sparsevec(double precision[], integer, boolean) TO anon;
GRANT ALL ON FUNCTION public.array_to_sparsevec(double precision[], integer, boolean) TO authenticated;
GRANT ALL ON FUNCTION public.array_to_sparsevec(double precision[], integer, boolean) TO service_role;


--
-- Name: FUNCTION array_to_vector(double precision[], integer, boolean); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.array_to_vector(double precision[], integer, boolean) TO postgres;
GRANT ALL ON FUNCTION public.array_to_vector(double precision[], integer, boolean) TO anon;
GRANT ALL ON FUNCTION public.array_to_vector(double precision[], integer, boolean) TO authenticated;
GRANT ALL ON FUNCTION public.array_to_vector(double precision[], integer, boolean) TO service_role;


--
-- Name: FUNCTION array_to_halfvec(integer[], integer, boolean); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.array_to_halfvec(integer[], integer, boolean) TO postgres;
GRANT ALL ON FUNCTION public.array_to_halfvec(integer[], integer, boolean) TO anon;
GRANT ALL ON FUNCTION public.array_to_halfvec(integer[], integer, boolean) TO authenticated;
GRANT ALL ON FUNCTION public.array_to_halfvec(integer[], integer, boolean) TO service_role;


--
-- Name: FUNCTION array_to_sparsevec(integer[], integer, boolean); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.array_to_sparsevec(integer[], integer, boolean) TO postgres;
GRANT ALL ON FUNCTION public.array_to_sparsevec(integer[], integer, boolean) TO anon;
GRANT ALL ON FUNCTION public.array_to_sparsevec(integer[], integer, boolean) TO authenticated;
GRANT ALL ON FUNCTION public.array_to_sparsevec(integer[], integer, boolean) TO service_role;


--
-- Name: FUNCTION array_to_vector(integer[], integer, boolean); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.array_to_vector(integer[], integer, boolean) TO postgres;
GRANT ALL ON FUNCTION public.array_to_vector(integer[], integer, boolean) TO anon;
GRANT ALL ON FUNCTION public.array_to_vector(integer[], integer, boolean) TO authenticated;
GRANT ALL ON FUNCTION public.array_to_vector(integer[], integer, boolean) TO service_role;


--
-- Name: FUNCTION array_to_halfvec(numeric[], integer, boolean); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.array_to_halfvec(numeric[], integer, boolean) TO postgres;
GRANT ALL ON FUNCTION public.array_to_halfvec(numeric[], integer, boolean) TO anon;
GRANT ALL ON FUNCTION public.array_to_halfvec(numeric[], integer, boolean) TO authenticated;
GRANT ALL ON FUNCTION public.array_to_halfvec(numeric[], integer, boolean) TO service_role;


--
-- Name: FUNCTION array_to_sparsevec(numeric[], integer, boolean); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.array_to_sparsevec(numeric[], integer, boolean) TO postgres;
GRANT ALL ON FUNCTION public.array_to_sparsevec(numeric[], integer, boolean) TO anon;
GRANT ALL ON FUNCTION public.array_to_sparsevec(numeric[], integer, boolean) TO authenticated;
GRANT ALL ON FUNCTION public.array_to_sparsevec(numeric[], integer, boolean) TO service_role;


--
-- Name: FUNCTION array_to_vector(numeric[], integer, boolean); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.array_to_vector(numeric[], integer, boolean) TO postgres;
GRANT ALL ON FUNCTION public.array_to_vector(numeric[], integer, boolean) TO anon;
GRANT ALL ON FUNCTION public.array_to_vector(numeric[], integer, boolean) TO authenticated;
GRANT ALL ON FUNCTION public.array_to_vector(numeric[], integer, boolean) TO service_role;


--
-- Name: FUNCTION halfvec_to_float4(public.halfvec, integer, boolean); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.halfvec_to_float4(public.halfvec, integer, boolean) TO postgres;
GRANT ALL ON FUNCTION public.halfvec_to_float4(public.halfvec, integer, boolean) TO anon;
GRANT ALL ON FUNCTION public.halfvec_to_float4(public.halfvec, integer, boolean) TO authenticated;
GRANT ALL ON FUNCTION public.halfvec_to_float4(public.halfvec, integer, boolean) TO service_role;


--
-- Name: FUNCTION halfvec(public.halfvec, integer, boolean); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.halfvec(public.halfvec, integer, boolean) TO postgres;
GRANT ALL ON FUNCTION public.halfvec(public.halfvec, integer, boolean) TO anon;
GRANT ALL ON FUNCTION public.halfvec(public.halfvec, integer, boolean) TO authenticated;
GRANT ALL ON FUNCTION public.halfvec(public.halfvec, integer, boolean) TO service_role;


--
-- Name: FUNCTION halfvec_to_sparsevec(public.halfvec, integer, boolean); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.halfvec_to_sparsevec(public.halfvec, integer, boolean) TO postgres;
GRANT ALL ON FUNCTION public.halfvec_to_sparsevec(public.halfvec, integer, boolean) TO anon;
GRANT ALL ON FUNCTION public.halfvec_to_sparsevec(public.halfvec, integer, boolean) TO authenticated;
GRANT ALL ON FUNCTION public.halfvec_to_sparsevec(public.halfvec, integer, boolean) TO service_role;


--
-- Name: FUNCTION halfvec_to_vector(public.halfvec, integer, boolean); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.halfvec_to_vector(public.halfvec, integer, boolean) TO postgres;
GRANT ALL ON FUNCTION public.halfvec_to_vector(public.halfvec, integer, boolean) TO anon;
GRANT ALL ON FUNCTION public.halfvec_to_vector(public.halfvec, integer, boolean) TO authenticated;
GRANT ALL ON FUNCTION public.halfvec_to_vector(public.halfvec, integer, boolean) TO service_role;


--
-- Name: FUNCTION sparsevec_to_halfvec(public.sparsevec, integer, boolean); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.sparsevec_to_halfvec(public.sparsevec, integer, boolean) TO postgres;
GRANT ALL ON FUNCTION public.sparsevec_to_halfvec(public.sparsevec, integer, boolean) TO anon;
GRANT ALL ON FUNCTION public.sparsevec_to_halfvec(public.sparsevec, integer, boolean) TO authenticated;
GRANT ALL ON FUNCTION public.sparsevec_to_halfvec(public.sparsevec, integer, boolean) TO service_role;


--
-- Name: FUNCTION sparsevec(public.sparsevec, integer, boolean); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.sparsevec(public.sparsevec, integer, boolean) TO postgres;
GRANT ALL ON FUNCTION public.sparsevec(public.sparsevec, integer, boolean) TO anon;
GRANT ALL ON FUNCTION public.sparsevec(public.sparsevec, integer, boolean) TO authenticated;
GRANT ALL ON FUNCTION public.sparsevec(public.sparsevec, integer, boolean) TO service_role;


--
-- Name: FUNCTION sparsevec_to_vector(public.sparsevec, integer, boolean); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.sparsevec_to_vector(public.sparsevec, integer, boolean) TO postgres;
GRANT ALL ON FUNCTION public.sparsevec_to_vector(public.sparsevec, integer, boolean) TO anon;
GRANT ALL ON FUNCTION public.sparsevec_to_vector(public.sparsevec, integer, boolean) TO authenticated;
GRANT ALL ON FUNCTION public.sparsevec_to_vector(public.sparsevec, integer, boolean) TO service_role;


--
-- Name: FUNCTION vector_to_float4(public.vector, integer, boolean); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.vector_to_float4(public.vector, integer, boolean) TO postgres;
GRANT ALL ON FUNCTION public.vector_to_float4(public.vector, integer, boolean) TO anon;
GRANT ALL ON FUNCTION public.vector_to_float4(public.vector, integer, boolean) TO authenticated;
GRANT ALL ON FUNCTION public.vector_to_float4(public.vector, integer, boolean) TO service_role;


--
-- Name: FUNCTION vector_to_halfvec(public.vector, integer, boolean); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.vector_to_halfvec(public.vector, integer, boolean) TO postgres;
GRANT ALL ON FUNCTION public.vector_to_halfvec(public.vector, integer, boolean) TO anon;
GRANT ALL ON FUNCTION public.vector_to_halfvec(public.vector, integer, boolean) TO authenticated;
GRANT ALL ON FUNCTION public.vector_to_halfvec(public.vector, integer, boolean) TO service_role;


--
-- Name: FUNCTION vector_to_sparsevec(public.vector, integer, boolean); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.vector_to_sparsevec(public.vector, integer, boolean) TO postgres;
GRANT ALL ON FUNCTION public.vector_to_sparsevec(public.vector, integer, boolean) TO anon;
GRANT ALL ON FUNCTION public.vector_to_sparsevec(public.vector, integer, boolean) TO authenticated;
GRANT ALL ON FUNCTION public.vector_to_sparsevec(public.vector, integer, boolean) TO service_role;


--
-- Name: FUNCTION vector(public.vector, integer, boolean); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.vector(public.vector, integer, boolean) TO postgres;
GRANT ALL ON FUNCTION public.vector(public.vector, integer, boolean) TO anon;
GRANT ALL ON FUNCTION public.vector(public.vector, integer, boolean) TO authenticated;
GRANT ALL ON FUNCTION public.vector(public.vector, integer, boolean) TO service_role;


--
-- Name: FUNCTION email(); Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT ALL ON FUNCTION auth.email() TO dashboard_user;
GRANT ALL ON FUNCTION auth.email() TO postgres;


--
-- Name: FUNCTION jwt(); Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT ALL ON FUNCTION auth.jwt() TO postgres;
GRANT ALL ON FUNCTION auth.jwt() TO dashboard_user;


--
-- Name: FUNCTION role(); Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT ALL ON FUNCTION auth.role() TO dashboard_user;
GRANT ALL ON FUNCTION auth.role() TO postgres;


--
-- Name: FUNCTION uid(); Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT ALL ON FUNCTION auth.uid() TO dashboard_user;
GRANT ALL ON FUNCTION auth.uid() TO postgres;


--
-- Name: FUNCTION armor(bytea); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.armor(bytea) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.armor(bytea) TO dashboard_user;


--
-- Name: FUNCTION armor(bytea, text[], text[]); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.armor(bytea, text[], text[]) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.armor(bytea, text[], text[]) TO dashboard_user;


--
-- Name: FUNCTION crypt(text, text); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.crypt(text, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.crypt(text, text) TO dashboard_user;


--
-- Name: FUNCTION dearmor(text); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.dearmor(text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.dearmor(text) TO dashboard_user;


--
-- Name: FUNCTION decrypt(bytea, bytea, text); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.decrypt(bytea, bytea, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.decrypt(bytea, bytea, text) TO dashboard_user;


--
-- Name: FUNCTION decrypt_iv(bytea, bytea, bytea, text); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.decrypt_iv(bytea, bytea, bytea, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.decrypt_iv(bytea, bytea, bytea, text) TO dashboard_user;


--
-- Name: FUNCTION digest(bytea, text); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.digest(bytea, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.digest(bytea, text) TO dashboard_user;


--
-- Name: FUNCTION digest(text, text); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.digest(text, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.digest(text, text) TO dashboard_user;


--
-- Name: FUNCTION encrypt(bytea, bytea, text); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.encrypt(bytea, bytea, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.encrypt(bytea, bytea, text) TO dashboard_user;


--
-- Name: FUNCTION encrypt_iv(bytea, bytea, bytea, text); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.encrypt_iv(bytea, bytea, bytea, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.encrypt_iv(bytea, bytea, bytea, text) TO dashboard_user;


--
-- Name: FUNCTION gen_random_bytes(integer); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.gen_random_bytes(integer) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.gen_random_bytes(integer) TO dashboard_user;


--
-- Name: FUNCTION gen_random_uuid(); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.gen_random_uuid() TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.gen_random_uuid() TO dashboard_user;


--
-- Name: FUNCTION gen_salt(text); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.gen_salt(text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.gen_salt(text) TO dashboard_user;


--
-- Name: FUNCTION gen_salt(text, integer); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.gen_salt(text, integer) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.gen_salt(text, integer) TO dashboard_user;


--
-- Name: FUNCTION grant_pg_cron_access(); Type: ACL; Schema: extensions; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION extensions.grant_pg_cron_access() FROM supabase_admin;
GRANT ALL ON FUNCTION extensions.grant_pg_cron_access() TO supabase_admin WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.grant_pg_cron_access() TO dashboard_user;
GRANT ALL ON FUNCTION extensions.grant_pg_cron_access() TO postgres WITH GRANT OPTION;


--
-- Name: FUNCTION grant_pg_graphql_access(); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.grant_pg_graphql_access() TO postgres WITH GRANT OPTION;


--
-- Name: FUNCTION grant_pg_net_access(); Type: ACL; Schema: extensions; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION extensions.grant_pg_net_access() FROM supabase_admin;
GRANT ALL ON FUNCTION extensions.grant_pg_net_access() TO supabase_admin WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.grant_pg_net_access() TO dashboard_user;
GRANT ALL ON FUNCTION extensions.grant_pg_net_access() TO postgres WITH GRANT OPTION;


--
-- Name: FUNCTION hmac(bytea, bytea, text); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.hmac(bytea, bytea, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.hmac(bytea, bytea, text) TO dashboard_user;


--
-- Name: FUNCTION hmac(text, text, text); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.hmac(text, text, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.hmac(text, text, text) TO dashboard_user;


--
-- Name: FUNCTION pg_stat_statements(showtext boolean, OUT userid oid, OUT dbid oid, OUT toplevel boolean, OUT queryid bigint, OUT query text, OUT plans bigint, OUT total_plan_time double precision, OUT min_plan_time double precision, OUT max_plan_time double precision, OUT mean_plan_time double precision, OUT stddev_plan_time double precision, OUT calls bigint, OUT total_exec_time double precision, OUT min_exec_time double precision, OUT max_exec_time double precision, OUT mean_exec_time double precision, OUT stddev_exec_time double precision, OUT rows bigint, OUT shared_blks_hit bigint, OUT shared_blks_read bigint, OUT shared_blks_dirtied bigint, OUT shared_blks_written bigint, OUT local_blks_hit bigint, OUT local_blks_read bigint, OUT local_blks_dirtied bigint, OUT local_blks_written bigint, OUT temp_blks_read bigint, OUT temp_blks_written bigint, OUT shared_blk_read_time double precision, OUT shared_blk_write_time double precision, OUT local_blk_read_time double precision, OUT local_blk_write_time double precision, OUT temp_blk_read_time double precision, OUT temp_blk_write_time double precision, OUT wal_records bigint, OUT wal_fpi bigint, OUT wal_bytes numeric, OUT jit_functions bigint, OUT jit_generation_time double precision, OUT jit_inlining_count bigint, OUT jit_inlining_time double precision, OUT jit_optimization_count bigint, OUT jit_optimization_time double precision, OUT jit_emission_count bigint, OUT jit_emission_time double precision, OUT jit_deform_count bigint, OUT jit_deform_time double precision, OUT stats_since timestamp with time zone, OUT minmax_stats_since timestamp with time zone); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.pg_stat_statements(showtext boolean, OUT userid oid, OUT dbid oid, OUT toplevel boolean, OUT queryid bigint, OUT query text, OUT plans bigint, OUT total_plan_time double precision, OUT min_plan_time double precision, OUT max_plan_time double precision, OUT mean_plan_time double precision, OUT stddev_plan_time double precision, OUT calls bigint, OUT total_exec_time double precision, OUT min_exec_time double precision, OUT max_exec_time double precision, OUT mean_exec_time double precision, OUT stddev_exec_time double precision, OUT rows bigint, OUT shared_blks_hit bigint, OUT shared_blks_read bigint, OUT shared_blks_dirtied bigint, OUT shared_blks_written bigint, OUT local_blks_hit bigint, OUT local_blks_read bigint, OUT local_blks_dirtied bigint, OUT local_blks_written bigint, OUT temp_blks_read bigint, OUT temp_blks_written bigint, OUT shared_blk_read_time double precision, OUT shared_blk_write_time double precision, OUT local_blk_read_time double precision, OUT local_blk_write_time double precision, OUT temp_blk_read_time double precision, OUT temp_blk_write_time double precision, OUT wal_records bigint, OUT wal_fpi bigint, OUT wal_bytes numeric, OUT jit_functions bigint, OUT jit_generation_time double precision, OUT jit_inlining_count bigint, OUT jit_inlining_time double precision, OUT jit_optimization_count bigint, OUT jit_optimization_time double precision, OUT jit_emission_count bigint, OUT jit_emission_time double precision, OUT jit_deform_count bigint, OUT jit_deform_time double precision, OUT stats_since timestamp with time zone, OUT minmax_stats_since timestamp with time zone) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pg_stat_statements(showtext boolean, OUT userid oid, OUT dbid oid, OUT toplevel boolean, OUT queryid bigint, OUT query text, OUT plans bigint, OUT total_plan_time double precision, OUT min_plan_time double precision, OUT max_plan_time double precision, OUT mean_plan_time double precision, OUT stddev_plan_time double precision, OUT calls bigint, OUT total_exec_time double precision, OUT min_exec_time double precision, OUT max_exec_time double precision, OUT mean_exec_time double precision, OUT stddev_exec_time double precision, OUT rows bigint, OUT shared_blks_hit bigint, OUT shared_blks_read bigint, OUT shared_blks_dirtied bigint, OUT shared_blks_written bigint, OUT local_blks_hit bigint, OUT local_blks_read bigint, OUT local_blks_dirtied bigint, OUT local_blks_written bigint, OUT temp_blks_read bigint, OUT temp_blks_written bigint, OUT shared_blk_read_time double precision, OUT shared_blk_write_time double precision, OUT local_blk_read_time double precision, OUT local_blk_write_time double precision, OUT temp_blk_read_time double precision, OUT temp_blk_write_time double precision, OUT wal_records bigint, OUT wal_fpi bigint, OUT wal_bytes numeric, OUT jit_functions bigint, OUT jit_generation_time double precision, OUT jit_inlining_count bigint, OUT jit_inlining_time double precision, OUT jit_optimization_count bigint, OUT jit_optimization_time double precision, OUT jit_emission_count bigint, OUT jit_emission_time double precision, OUT jit_deform_count bigint, OUT jit_deform_time double precision, OUT stats_since timestamp with time zone, OUT minmax_stats_since timestamp with time zone) TO dashboard_user;


--
-- Name: FUNCTION pg_stat_statements_info(OUT dealloc bigint, OUT stats_reset timestamp with time zone); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.pg_stat_statements_info(OUT dealloc bigint, OUT stats_reset timestamp with time zone) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pg_stat_statements_info(OUT dealloc bigint, OUT stats_reset timestamp with time zone) TO dashboard_user;


--
-- Name: FUNCTION pg_stat_statements_reset(userid oid, dbid oid, queryid bigint, minmax_only boolean); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.pg_stat_statements_reset(userid oid, dbid oid, queryid bigint, minmax_only boolean) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pg_stat_statements_reset(userid oid, dbid oid, queryid bigint, minmax_only boolean) TO dashboard_user;


--
-- Name: FUNCTION pgp_armor_headers(text, OUT key text, OUT value text); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.pgp_armor_headers(text, OUT key text, OUT value text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_armor_headers(text, OUT key text, OUT value text) TO dashboard_user;


--
-- Name: FUNCTION pgp_key_id(bytea); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.pgp_key_id(bytea) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_key_id(bytea) TO dashboard_user;


--
-- Name: FUNCTION pgp_pub_decrypt(bytea, bytea); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.pgp_pub_decrypt(bytea, bytea) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_pub_decrypt(bytea, bytea) TO dashboard_user;


--
-- Name: FUNCTION pgp_pub_decrypt(bytea, bytea, text); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.pgp_pub_decrypt(bytea, bytea, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_pub_decrypt(bytea, bytea, text) TO dashboard_user;


--
-- Name: FUNCTION pgp_pub_decrypt(bytea, bytea, text, text); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.pgp_pub_decrypt(bytea, bytea, text, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_pub_decrypt(bytea, bytea, text, text) TO dashboard_user;


--
-- Name: FUNCTION pgp_pub_decrypt_bytea(bytea, bytea); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.pgp_pub_decrypt_bytea(bytea, bytea) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_pub_decrypt_bytea(bytea, bytea) TO dashboard_user;


--
-- Name: FUNCTION pgp_pub_decrypt_bytea(bytea, bytea, text); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.pgp_pub_decrypt_bytea(bytea, bytea, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_pub_decrypt_bytea(bytea, bytea, text) TO dashboard_user;


--
-- Name: FUNCTION pgp_pub_decrypt_bytea(bytea, bytea, text, text); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.pgp_pub_decrypt_bytea(bytea, bytea, text, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_pub_decrypt_bytea(bytea, bytea, text, text) TO dashboard_user;


--
-- Name: FUNCTION pgp_pub_encrypt(text, bytea); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.pgp_pub_encrypt(text, bytea) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_pub_encrypt(text, bytea) TO dashboard_user;


--
-- Name: FUNCTION pgp_pub_encrypt(text, bytea, text); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.pgp_pub_encrypt(text, bytea, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_pub_encrypt(text, bytea, text) TO dashboard_user;


--
-- Name: FUNCTION pgp_pub_encrypt_bytea(bytea, bytea); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.pgp_pub_encrypt_bytea(bytea, bytea) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_pub_encrypt_bytea(bytea, bytea) TO dashboard_user;


--
-- Name: FUNCTION pgp_pub_encrypt_bytea(bytea, bytea, text); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.pgp_pub_encrypt_bytea(bytea, bytea, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_pub_encrypt_bytea(bytea, bytea, text) TO dashboard_user;


--
-- Name: FUNCTION pgp_sym_decrypt(bytea, text); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.pgp_sym_decrypt(bytea, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_sym_decrypt(bytea, text) TO dashboard_user;


--
-- Name: FUNCTION pgp_sym_decrypt(bytea, text, text); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.pgp_sym_decrypt(bytea, text, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_sym_decrypt(bytea, text, text) TO dashboard_user;


--
-- Name: FUNCTION pgp_sym_decrypt_bytea(bytea, text); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.pgp_sym_decrypt_bytea(bytea, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_sym_decrypt_bytea(bytea, text) TO dashboard_user;


--
-- Name: FUNCTION pgp_sym_decrypt_bytea(bytea, text, text); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.pgp_sym_decrypt_bytea(bytea, text, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_sym_decrypt_bytea(bytea, text, text) TO dashboard_user;


--
-- Name: FUNCTION pgp_sym_encrypt(text, text); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.pgp_sym_encrypt(text, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_sym_encrypt(text, text) TO dashboard_user;


--
-- Name: FUNCTION pgp_sym_encrypt(text, text, text); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.pgp_sym_encrypt(text, text, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_sym_encrypt(text, text, text) TO dashboard_user;


--
-- Name: FUNCTION pgp_sym_encrypt_bytea(bytea, text); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.pgp_sym_encrypt_bytea(bytea, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_sym_encrypt_bytea(bytea, text) TO dashboard_user;


--
-- Name: FUNCTION pgp_sym_encrypt_bytea(bytea, text, text); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.pgp_sym_encrypt_bytea(bytea, text, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_sym_encrypt_bytea(bytea, text, text) TO dashboard_user;


--
-- Name: FUNCTION pgrst_ddl_watch(); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.pgrst_ddl_watch() TO postgres WITH GRANT OPTION;


--
-- Name: FUNCTION pgrst_drop_watch(); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.pgrst_drop_watch() TO postgres WITH GRANT OPTION;


--
-- Name: FUNCTION set_graphql_placeholder(); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.set_graphql_placeholder() TO postgres WITH GRANT OPTION;


--
-- Name: FUNCTION uuid_generate_v1(); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.uuid_generate_v1() TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.uuid_generate_v1() TO dashboard_user;


--
-- Name: FUNCTION uuid_generate_v1mc(); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.uuid_generate_v1mc() TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.uuid_generate_v1mc() TO dashboard_user;


--
-- Name: FUNCTION uuid_generate_v3(namespace uuid, name text); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.uuid_generate_v3(namespace uuid, name text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.uuid_generate_v3(namespace uuid, name text) TO dashboard_user;


--
-- Name: FUNCTION uuid_generate_v4(); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.uuid_generate_v4() TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.uuid_generate_v4() TO dashboard_user;


--
-- Name: FUNCTION uuid_generate_v5(namespace uuid, name text); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.uuid_generate_v5(namespace uuid, name text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.uuid_generate_v5(namespace uuid, name text) TO dashboard_user;


--
-- Name: FUNCTION uuid_nil(); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.uuid_nil() TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.uuid_nil() TO dashboard_user;


--
-- Name: FUNCTION uuid_ns_dns(); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.uuid_ns_dns() TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.uuid_ns_dns() TO dashboard_user;


--
-- Name: FUNCTION uuid_ns_oid(); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.uuid_ns_oid() TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.uuid_ns_oid() TO dashboard_user;


--
-- Name: FUNCTION uuid_ns_url(); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.uuid_ns_url() TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.uuid_ns_url() TO dashboard_user;


--
-- Name: FUNCTION uuid_ns_x500(); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.uuid_ns_x500() TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.uuid_ns_x500() TO dashboard_user;


--
-- Name: FUNCTION graphql("operationName" text, query text, variables jsonb, extensions jsonb); Type: ACL; Schema: graphql_public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION graphql_public.graphql("operationName" text, query text, variables jsonb, extensions jsonb) TO postgres;
GRANT ALL ON FUNCTION graphql_public.graphql("operationName" text, query text, variables jsonb, extensions jsonb) TO anon;
GRANT ALL ON FUNCTION graphql_public.graphql("operationName" text, query text, variables jsonb, extensions jsonb) TO authenticated;
GRANT ALL ON FUNCTION graphql_public.graphql("operationName" text, query text, variables jsonb, extensions jsonb) TO service_role;


--
-- Name: FUNCTION get_auth(p_usename text); Type: ACL; Schema: pgbouncer; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION pgbouncer.get_auth(p_usename text) FROM PUBLIC;
GRANT ALL ON FUNCTION pgbouncer.get_auth(p_usename text) TO pgbouncer;


--
-- Name: FUNCTION binary_quantize(public.halfvec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.binary_quantize(public.halfvec) TO postgres;
GRANT ALL ON FUNCTION public.binary_quantize(public.halfvec) TO anon;
GRANT ALL ON FUNCTION public.binary_quantize(public.halfvec) TO authenticated;
GRANT ALL ON FUNCTION public.binary_quantize(public.halfvec) TO service_role;


--
-- Name: FUNCTION binary_quantize(public.vector); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.binary_quantize(public.vector) TO postgres;
GRANT ALL ON FUNCTION public.binary_quantize(public.vector) TO anon;
GRANT ALL ON FUNCTION public.binary_quantize(public.vector) TO authenticated;
GRANT ALL ON FUNCTION public.binary_quantize(public.vector) TO service_role;


--
-- Name: FUNCTION cosine_distance(public.halfvec, public.halfvec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.cosine_distance(public.halfvec, public.halfvec) TO postgres;
GRANT ALL ON FUNCTION public.cosine_distance(public.halfvec, public.halfvec) TO anon;
GRANT ALL ON FUNCTION public.cosine_distance(public.halfvec, public.halfvec) TO authenticated;
GRANT ALL ON FUNCTION public.cosine_distance(public.halfvec, public.halfvec) TO service_role;


--
-- Name: FUNCTION cosine_distance(public.sparsevec, public.sparsevec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.cosine_distance(public.sparsevec, public.sparsevec) TO postgres;
GRANT ALL ON FUNCTION public.cosine_distance(public.sparsevec, public.sparsevec) TO anon;
GRANT ALL ON FUNCTION public.cosine_distance(public.sparsevec, public.sparsevec) TO authenticated;
GRANT ALL ON FUNCTION public.cosine_distance(public.sparsevec, public.sparsevec) TO service_role;


--
-- Name: FUNCTION cosine_distance(public.vector, public.vector); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.cosine_distance(public.vector, public.vector) TO postgres;
GRANT ALL ON FUNCTION public.cosine_distance(public.vector, public.vector) TO anon;
GRANT ALL ON FUNCTION public.cosine_distance(public.vector, public.vector) TO authenticated;
GRANT ALL ON FUNCTION public.cosine_distance(public.vector, public.vector) TO service_role;


--
-- Name: FUNCTION export_template_csv(p_organization_id text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.export_template_csv(p_organization_id text) TO anon;
GRANT ALL ON FUNCTION public.export_template_csv(p_organization_id text) TO authenticated;
GRANT ALL ON FUNCTION public.export_template_csv(p_organization_id text) TO service_role;


--
-- Name: FUNCTION get_companies_by_campaign(p_organization_id text, p_campaign_id uuid, p_status text, p_search text, p_sort_by text, p_sort_order text, p_page integer, p_limit integer); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.get_companies_by_campaign(p_organization_id text, p_campaign_id uuid, p_status text, p_search text, p_sort_by text, p_sort_order text, p_page integer, p_limit integer) TO anon;
GRANT ALL ON FUNCTION public.get_companies_by_campaign(p_organization_id text, p_campaign_id uuid, p_status text, p_search text, p_sort_by text, p_sort_order text, p_page integer, p_limit integer) TO authenticated;
GRANT ALL ON FUNCTION public.get_companies_by_campaign(p_organization_id text, p_campaign_id uuid, p_status text, p_search text, p_sort_by text, p_sort_order text, p_page integer, p_limit integer) TO service_role;


--
-- Name: FUNCTION get_dashboard_stats(p_organization_id text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.get_dashboard_stats(p_organization_id text) TO anon;
GRANT ALL ON FUNCTION public.get_dashboard_stats(p_organization_id text) TO authenticated;
GRANT ALL ON FUNCTION public.get_dashboard_stats(p_organization_id text) TO service_role;


--
-- Name: FUNCTION get_organization_summary(p_organization_id text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.get_organization_summary(p_organization_id text) TO anon;
GRANT ALL ON FUNCTION public.get_organization_summary(p_organization_id text) TO authenticated;
GRANT ALL ON FUNCTION public.get_organization_summary(p_organization_id text) TO service_role;


--
-- Name: FUNCTION get_sales_pipeline_analytics(org_id text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.get_sales_pipeline_analytics(org_id text) TO anon;
GRANT ALL ON FUNCTION public.get_sales_pipeline_analytics(org_id text) TO authenticated;
GRANT ALL ON FUNCTION public.get_sales_pipeline_analytics(org_id text) TO service_role;


--
-- Name: FUNCTION get_token_usage_stats(p_organization_id text, p_start_date date, p_end_date date, p_model_name text, p_campaign_id text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.get_token_usage_stats(p_organization_id text, p_start_date date, p_end_date date, p_model_name text, p_campaign_id text) TO anon;
GRANT ALL ON FUNCTION public.get_token_usage_stats(p_organization_id text, p_start_date date, p_end_date date, p_model_name text, p_campaign_id text) TO authenticated;
GRANT ALL ON FUNCTION public.get_token_usage_stats(p_organization_id text, p_start_date date, p_end_date date, p_model_name text, p_campaign_id text) TO service_role;


--
-- Name: FUNCTION get_token_usage_summary(p_organization_id text, p_start_date date, p_end_date date, p_model_name text, p_campaign_id text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.get_token_usage_summary(p_organization_id text, p_start_date date, p_end_date date, p_model_name text, p_campaign_id text) TO anon;
GRANT ALL ON FUNCTION public.get_token_usage_summary(p_organization_id text, p_start_date date, p_end_date date, p_model_name text, p_campaign_id text) TO authenticated;
GRANT ALL ON FUNCTION public.get_token_usage_summary(p_organization_id text, p_start_date date, p_end_date date, p_model_name text, p_campaign_id text) TO service_role;


--
-- Name: FUNCTION gin_extract_query_trgm(text, internal, smallint, internal, internal, internal, internal); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.gin_extract_query_trgm(text, internal, smallint, internal, internal, internal, internal) TO postgres;
GRANT ALL ON FUNCTION public.gin_extract_query_trgm(text, internal, smallint, internal, internal, internal, internal) TO anon;
GRANT ALL ON FUNCTION public.gin_extract_query_trgm(text, internal, smallint, internal, internal, internal, internal) TO authenticated;
GRANT ALL ON FUNCTION public.gin_extract_query_trgm(text, internal, smallint, internal, internal, internal, internal) TO service_role;


--
-- Name: FUNCTION gin_extract_value_trgm(text, internal); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.gin_extract_value_trgm(text, internal) TO postgres;
GRANT ALL ON FUNCTION public.gin_extract_value_trgm(text, internal) TO anon;
GRANT ALL ON FUNCTION public.gin_extract_value_trgm(text, internal) TO authenticated;
GRANT ALL ON FUNCTION public.gin_extract_value_trgm(text, internal) TO service_role;


--
-- Name: FUNCTION gin_trgm_consistent(internal, smallint, text, integer, internal, internal, internal, internal); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.gin_trgm_consistent(internal, smallint, text, integer, internal, internal, internal, internal) TO postgres;
GRANT ALL ON FUNCTION public.gin_trgm_consistent(internal, smallint, text, integer, internal, internal, internal, internal) TO anon;
GRANT ALL ON FUNCTION public.gin_trgm_consistent(internal, smallint, text, integer, internal, internal, internal, internal) TO authenticated;
GRANT ALL ON FUNCTION public.gin_trgm_consistent(internal, smallint, text, integer, internal, internal, internal, internal) TO service_role;


--
-- Name: FUNCTION gin_trgm_triconsistent(internal, smallint, text, integer, internal, internal, internal); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.gin_trgm_triconsistent(internal, smallint, text, integer, internal, internal, internal) TO postgres;
GRANT ALL ON FUNCTION public.gin_trgm_triconsistent(internal, smallint, text, integer, internal, internal, internal) TO anon;
GRANT ALL ON FUNCTION public.gin_trgm_triconsistent(internal, smallint, text, integer, internal, internal, internal) TO authenticated;
GRANT ALL ON FUNCTION public.gin_trgm_triconsistent(internal, smallint, text, integer, internal, internal, internal) TO service_role;


--
-- Name: FUNCTION gtrgm_compress(internal); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.gtrgm_compress(internal) TO postgres;
GRANT ALL ON FUNCTION public.gtrgm_compress(internal) TO anon;
GRANT ALL ON FUNCTION public.gtrgm_compress(internal) TO authenticated;
GRANT ALL ON FUNCTION public.gtrgm_compress(internal) TO service_role;


--
-- Name: FUNCTION gtrgm_consistent(internal, text, smallint, oid, internal); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.gtrgm_consistent(internal, text, smallint, oid, internal) TO postgres;
GRANT ALL ON FUNCTION public.gtrgm_consistent(internal, text, smallint, oid, internal) TO anon;
GRANT ALL ON FUNCTION public.gtrgm_consistent(internal, text, smallint, oid, internal) TO authenticated;
GRANT ALL ON FUNCTION public.gtrgm_consistent(internal, text, smallint, oid, internal) TO service_role;


--
-- Name: FUNCTION gtrgm_decompress(internal); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.gtrgm_decompress(internal) TO postgres;
GRANT ALL ON FUNCTION public.gtrgm_decompress(internal) TO anon;
GRANT ALL ON FUNCTION public.gtrgm_decompress(internal) TO authenticated;
GRANT ALL ON FUNCTION public.gtrgm_decompress(internal) TO service_role;


--
-- Name: FUNCTION gtrgm_distance(internal, text, smallint, oid, internal); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.gtrgm_distance(internal, text, smallint, oid, internal) TO postgres;
GRANT ALL ON FUNCTION public.gtrgm_distance(internal, text, smallint, oid, internal) TO anon;
GRANT ALL ON FUNCTION public.gtrgm_distance(internal, text, smallint, oid, internal) TO authenticated;
GRANT ALL ON FUNCTION public.gtrgm_distance(internal, text, smallint, oid, internal) TO service_role;


--
-- Name: FUNCTION gtrgm_options(internal); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.gtrgm_options(internal) TO postgres;
GRANT ALL ON FUNCTION public.gtrgm_options(internal) TO anon;
GRANT ALL ON FUNCTION public.gtrgm_options(internal) TO authenticated;
GRANT ALL ON FUNCTION public.gtrgm_options(internal) TO service_role;


--
-- Name: FUNCTION gtrgm_penalty(internal, internal, internal); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.gtrgm_penalty(internal, internal, internal) TO postgres;
GRANT ALL ON FUNCTION public.gtrgm_penalty(internal, internal, internal) TO anon;
GRANT ALL ON FUNCTION public.gtrgm_penalty(internal, internal, internal) TO authenticated;
GRANT ALL ON FUNCTION public.gtrgm_penalty(internal, internal, internal) TO service_role;


--
-- Name: FUNCTION gtrgm_picksplit(internal, internal); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.gtrgm_picksplit(internal, internal) TO postgres;
GRANT ALL ON FUNCTION public.gtrgm_picksplit(internal, internal) TO anon;
GRANT ALL ON FUNCTION public.gtrgm_picksplit(internal, internal) TO authenticated;
GRANT ALL ON FUNCTION public.gtrgm_picksplit(internal, internal) TO service_role;


--
-- Name: FUNCTION gtrgm_same(public.gtrgm, public.gtrgm, internal); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.gtrgm_same(public.gtrgm, public.gtrgm, internal) TO postgres;
GRANT ALL ON FUNCTION public.gtrgm_same(public.gtrgm, public.gtrgm, internal) TO anon;
GRANT ALL ON FUNCTION public.gtrgm_same(public.gtrgm, public.gtrgm, internal) TO authenticated;
GRANT ALL ON FUNCTION public.gtrgm_same(public.gtrgm, public.gtrgm, internal) TO service_role;


--
-- Name: FUNCTION gtrgm_union(internal, internal); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.gtrgm_union(internal, internal) TO postgres;
GRANT ALL ON FUNCTION public.gtrgm_union(internal, internal) TO anon;
GRANT ALL ON FUNCTION public.gtrgm_union(internal, internal) TO authenticated;
GRANT ALL ON FUNCTION public.gtrgm_union(internal, internal) TO service_role;


--
-- Name: FUNCTION halfvec_accum(double precision[], public.halfvec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.halfvec_accum(double precision[], public.halfvec) TO postgres;
GRANT ALL ON FUNCTION public.halfvec_accum(double precision[], public.halfvec) TO anon;
GRANT ALL ON FUNCTION public.halfvec_accum(double precision[], public.halfvec) TO authenticated;
GRANT ALL ON FUNCTION public.halfvec_accum(double precision[], public.halfvec) TO service_role;


--
-- Name: FUNCTION halfvec_add(public.halfvec, public.halfvec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.halfvec_add(public.halfvec, public.halfvec) TO postgres;
GRANT ALL ON FUNCTION public.halfvec_add(public.halfvec, public.halfvec) TO anon;
GRANT ALL ON FUNCTION public.halfvec_add(public.halfvec, public.halfvec) TO authenticated;
GRANT ALL ON FUNCTION public.halfvec_add(public.halfvec, public.halfvec) TO service_role;


--
-- Name: FUNCTION halfvec_avg(double precision[]); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.halfvec_avg(double precision[]) TO postgres;
GRANT ALL ON FUNCTION public.halfvec_avg(double precision[]) TO anon;
GRANT ALL ON FUNCTION public.halfvec_avg(double precision[]) TO authenticated;
GRANT ALL ON FUNCTION public.halfvec_avg(double precision[]) TO service_role;


--
-- Name: FUNCTION halfvec_cmp(public.halfvec, public.halfvec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.halfvec_cmp(public.halfvec, public.halfvec) TO postgres;
GRANT ALL ON FUNCTION public.halfvec_cmp(public.halfvec, public.halfvec) TO anon;
GRANT ALL ON FUNCTION public.halfvec_cmp(public.halfvec, public.halfvec) TO authenticated;
GRANT ALL ON FUNCTION public.halfvec_cmp(public.halfvec, public.halfvec) TO service_role;


--
-- Name: FUNCTION halfvec_combine(double precision[], double precision[]); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.halfvec_combine(double precision[], double precision[]) TO postgres;
GRANT ALL ON FUNCTION public.halfvec_combine(double precision[], double precision[]) TO anon;
GRANT ALL ON FUNCTION public.halfvec_combine(double precision[], double precision[]) TO authenticated;
GRANT ALL ON FUNCTION public.halfvec_combine(double precision[], double precision[]) TO service_role;


--
-- Name: FUNCTION halfvec_concat(public.halfvec, public.halfvec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.halfvec_concat(public.halfvec, public.halfvec) TO postgres;
GRANT ALL ON FUNCTION public.halfvec_concat(public.halfvec, public.halfvec) TO anon;
GRANT ALL ON FUNCTION public.halfvec_concat(public.halfvec, public.halfvec) TO authenticated;
GRANT ALL ON FUNCTION public.halfvec_concat(public.halfvec, public.halfvec) TO service_role;


--
-- Name: FUNCTION halfvec_eq(public.halfvec, public.halfvec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.halfvec_eq(public.halfvec, public.halfvec) TO postgres;
GRANT ALL ON FUNCTION public.halfvec_eq(public.halfvec, public.halfvec) TO anon;
GRANT ALL ON FUNCTION public.halfvec_eq(public.halfvec, public.halfvec) TO authenticated;
GRANT ALL ON FUNCTION public.halfvec_eq(public.halfvec, public.halfvec) TO service_role;


--
-- Name: FUNCTION halfvec_ge(public.halfvec, public.halfvec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.halfvec_ge(public.halfvec, public.halfvec) TO postgres;
GRANT ALL ON FUNCTION public.halfvec_ge(public.halfvec, public.halfvec) TO anon;
GRANT ALL ON FUNCTION public.halfvec_ge(public.halfvec, public.halfvec) TO authenticated;
GRANT ALL ON FUNCTION public.halfvec_ge(public.halfvec, public.halfvec) TO service_role;


--
-- Name: FUNCTION halfvec_gt(public.halfvec, public.halfvec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.halfvec_gt(public.halfvec, public.halfvec) TO postgres;
GRANT ALL ON FUNCTION public.halfvec_gt(public.halfvec, public.halfvec) TO anon;
GRANT ALL ON FUNCTION public.halfvec_gt(public.halfvec, public.halfvec) TO authenticated;
GRANT ALL ON FUNCTION public.halfvec_gt(public.halfvec, public.halfvec) TO service_role;


--
-- Name: FUNCTION halfvec_l2_squared_distance(public.halfvec, public.halfvec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.halfvec_l2_squared_distance(public.halfvec, public.halfvec) TO postgres;
GRANT ALL ON FUNCTION public.halfvec_l2_squared_distance(public.halfvec, public.halfvec) TO anon;
GRANT ALL ON FUNCTION public.halfvec_l2_squared_distance(public.halfvec, public.halfvec) TO authenticated;
GRANT ALL ON FUNCTION public.halfvec_l2_squared_distance(public.halfvec, public.halfvec) TO service_role;


--
-- Name: FUNCTION halfvec_le(public.halfvec, public.halfvec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.halfvec_le(public.halfvec, public.halfvec) TO postgres;
GRANT ALL ON FUNCTION public.halfvec_le(public.halfvec, public.halfvec) TO anon;
GRANT ALL ON FUNCTION public.halfvec_le(public.halfvec, public.halfvec) TO authenticated;
GRANT ALL ON FUNCTION public.halfvec_le(public.halfvec, public.halfvec) TO service_role;


--
-- Name: FUNCTION halfvec_lt(public.halfvec, public.halfvec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.halfvec_lt(public.halfvec, public.halfvec) TO postgres;
GRANT ALL ON FUNCTION public.halfvec_lt(public.halfvec, public.halfvec) TO anon;
GRANT ALL ON FUNCTION public.halfvec_lt(public.halfvec, public.halfvec) TO authenticated;
GRANT ALL ON FUNCTION public.halfvec_lt(public.halfvec, public.halfvec) TO service_role;


--
-- Name: FUNCTION halfvec_mul(public.halfvec, public.halfvec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.halfvec_mul(public.halfvec, public.halfvec) TO postgres;
GRANT ALL ON FUNCTION public.halfvec_mul(public.halfvec, public.halfvec) TO anon;
GRANT ALL ON FUNCTION public.halfvec_mul(public.halfvec, public.halfvec) TO authenticated;
GRANT ALL ON FUNCTION public.halfvec_mul(public.halfvec, public.halfvec) TO service_role;


--
-- Name: FUNCTION halfvec_ne(public.halfvec, public.halfvec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.halfvec_ne(public.halfvec, public.halfvec) TO postgres;
GRANT ALL ON FUNCTION public.halfvec_ne(public.halfvec, public.halfvec) TO anon;
GRANT ALL ON FUNCTION public.halfvec_ne(public.halfvec, public.halfvec) TO authenticated;
GRANT ALL ON FUNCTION public.halfvec_ne(public.halfvec, public.halfvec) TO service_role;


--
-- Name: FUNCTION halfvec_negative_inner_product(public.halfvec, public.halfvec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.halfvec_negative_inner_product(public.halfvec, public.halfvec) TO postgres;
GRANT ALL ON FUNCTION public.halfvec_negative_inner_product(public.halfvec, public.halfvec) TO anon;
GRANT ALL ON FUNCTION public.halfvec_negative_inner_product(public.halfvec, public.halfvec) TO authenticated;
GRANT ALL ON FUNCTION public.halfvec_negative_inner_product(public.halfvec, public.halfvec) TO service_role;


--
-- Name: FUNCTION halfvec_spherical_distance(public.halfvec, public.halfvec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.halfvec_spherical_distance(public.halfvec, public.halfvec) TO postgres;
GRANT ALL ON FUNCTION public.halfvec_spherical_distance(public.halfvec, public.halfvec) TO anon;
GRANT ALL ON FUNCTION public.halfvec_spherical_distance(public.halfvec, public.halfvec) TO authenticated;
GRANT ALL ON FUNCTION public.halfvec_spherical_distance(public.halfvec, public.halfvec) TO service_role;


--
-- Name: FUNCTION halfvec_sub(public.halfvec, public.halfvec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.halfvec_sub(public.halfvec, public.halfvec) TO postgres;
GRANT ALL ON FUNCTION public.halfvec_sub(public.halfvec, public.halfvec) TO anon;
GRANT ALL ON FUNCTION public.halfvec_sub(public.halfvec, public.halfvec) TO authenticated;
GRANT ALL ON FUNCTION public.halfvec_sub(public.halfvec, public.halfvec) TO service_role;


--
-- Name: FUNCTION hamming_distance(bit, bit); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.hamming_distance(bit, bit) TO postgres;
GRANT ALL ON FUNCTION public.hamming_distance(bit, bit) TO anon;
GRANT ALL ON FUNCTION public.hamming_distance(bit, bit) TO authenticated;
GRANT ALL ON FUNCTION public.hamming_distance(bit, bit) TO service_role;


--
-- Name: FUNCTION hnsw_bit_support(internal); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.hnsw_bit_support(internal) TO postgres;
GRANT ALL ON FUNCTION public.hnsw_bit_support(internal) TO anon;
GRANT ALL ON FUNCTION public.hnsw_bit_support(internal) TO authenticated;
GRANT ALL ON FUNCTION public.hnsw_bit_support(internal) TO service_role;


--
-- Name: FUNCTION hnsw_halfvec_support(internal); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.hnsw_halfvec_support(internal) TO postgres;
GRANT ALL ON FUNCTION public.hnsw_halfvec_support(internal) TO anon;
GRANT ALL ON FUNCTION public.hnsw_halfvec_support(internal) TO authenticated;
GRANT ALL ON FUNCTION public.hnsw_halfvec_support(internal) TO service_role;


--
-- Name: FUNCTION hnsw_sparsevec_support(internal); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.hnsw_sparsevec_support(internal) TO postgres;
GRANT ALL ON FUNCTION public.hnsw_sparsevec_support(internal) TO anon;
GRANT ALL ON FUNCTION public.hnsw_sparsevec_support(internal) TO authenticated;
GRANT ALL ON FUNCTION public.hnsw_sparsevec_support(internal) TO service_role;


--
-- Name: FUNCTION hnswhandler(internal); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.hnswhandler(internal) TO postgres;
GRANT ALL ON FUNCTION public.hnswhandler(internal) TO anon;
GRANT ALL ON FUNCTION public.hnswhandler(internal) TO authenticated;
GRANT ALL ON FUNCTION public.hnswhandler(internal) TO service_role;


--
-- Name: FUNCTION inner_product(public.halfvec, public.halfvec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.inner_product(public.halfvec, public.halfvec) TO postgres;
GRANT ALL ON FUNCTION public.inner_product(public.halfvec, public.halfvec) TO anon;
GRANT ALL ON FUNCTION public.inner_product(public.halfvec, public.halfvec) TO authenticated;
GRANT ALL ON FUNCTION public.inner_product(public.halfvec, public.halfvec) TO service_role;


--
-- Name: FUNCTION inner_product(public.sparsevec, public.sparsevec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.inner_product(public.sparsevec, public.sparsevec) TO postgres;
GRANT ALL ON FUNCTION public.inner_product(public.sparsevec, public.sparsevec) TO anon;
GRANT ALL ON FUNCTION public.inner_product(public.sparsevec, public.sparsevec) TO authenticated;
GRANT ALL ON FUNCTION public.inner_product(public.sparsevec, public.sparsevec) TO service_role;


--
-- Name: FUNCTION inner_product(public.vector, public.vector); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.inner_product(public.vector, public.vector) TO postgres;
GRANT ALL ON FUNCTION public.inner_product(public.vector, public.vector) TO anon;
GRANT ALL ON FUNCTION public.inner_product(public.vector, public.vector) TO authenticated;
GRANT ALL ON FUNCTION public.inner_product(public.vector, public.vector) TO service_role;


--
-- Name: FUNCTION ivfflat_bit_support(internal); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.ivfflat_bit_support(internal) TO postgres;
GRANT ALL ON FUNCTION public.ivfflat_bit_support(internal) TO anon;
GRANT ALL ON FUNCTION public.ivfflat_bit_support(internal) TO authenticated;
GRANT ALL ON FUNCTION public.ivfflat_bit_support(internal) TO service_role;


--
-- Name: FUNCTION ivfflat_halfvec_support(internal); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.ivfflat_halfvec_support(internal) TO postgres;
GRANT ALL ON FUNCTION public.ivfflat_halfvec_support(internal) TO anon;
GRANT ALL ON FUNCTION public.ivfflat_halfvec_support(internal) TO authenticated;
GRANT ALL ON FUNCTION public.ivfflat_halfvec_support(internal) TO service_role;


--
-- Name: FUNCTION ivfflathandler(internal); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.ivfflathandler(internal) TO postgres;
GRANT ALL ON FUNCTION public.ivfflathandler(internal) TO anon;
GRANT ALL ON FUNCTION public.ivfflathandler(internal) TO authenticated;
GRANT ALL ON FUNCTION public.ivfflathandler(internal) TO service_role;


--
-- Name: FUNCTION jaccard_distance(bit, bit); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.jaccard_distance(bit, bit) TO postgres;
GRANT ALL ON FUNCTION public.jaccard_distance(bit, bit) TO anon;
GRANT ALL ON FUNCTION public.jaccard_distance(bit, bit) TO authenticated;
GRANT ALL ON FUNCTION public.jaccard_distance(bit, bit) TO service_role;


--
-- Name: FUNCTION l1_distance(public.halfvec, public.halfvec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.l1_distance(public.halfvec, public.halfvec) TO postgres;
GRANT ALL ON FUNCTION public.l1_distance(public.halfvec, public.halfvec) TO anon;
GRANT ALL ON FUNCTION public.l1_distance(public.halfvec, public.halfvec) TO authenticated;
GRANT ALL ON FUNCTION public.l1_distance(public.halfvec, public.halfvec) TO service_role;


--
-- Name: FUNCTION l1_distance(public.sparsevec, public.sparsevec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.l1_distance(public.sparsevec, public.sparsevec) TO postgres;
GRANT ALL ON FUNCTION public.l1_distance(public.sparsevec, public.sparsevec) TO anon;
GRANT ALL ON FUNCTION public.l1_distance(public.sparsevec, public.sparsevec) TO authenticated;
GRANT ALL ON FUNCTION public.l1_distance(public.sparsevec, public.sparsevec) TO service_role;


--
-- Name: FUNCTION l1_distance(public.vector, public.vector); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.l1_distance(public.vector, public.vector) TO postgres;
GRANT ALL ON FUNCTION public.l1_distance(public.vector, public.vector) TO anon;
GRANT ALL ON FUNCTION public.l1_distance(public.vector, public.vector) TO authenticated;
GRANT ALL ON FUNCTION public.l1_distance(public.vector, public.vector) TO service_role;


--
-- Name: FUNCTION l2_distance(public.halfvec, public.halfvec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.l2_distance(public.halfvec, public.halfvec) TO postgres;
GRANT ALL ON FUNCTION public.l2_distance(public.halfvec, public.halfvec) TO anon;
GRANT ALL ON FUNCTION public.l2_distance(public.halfvec, public.halfvec) TO authenticated;
GRANT ALL ON FUNCTION public.l2_distance(public.halfvec, public.halfvec) TO service_role;


--
-- Name: FUNCTION l2_distance(public.sparsevec, public.sparsevec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.l2_distance(public.sparsevec, public.sparsevec) TO postgres;
GRANT ALL ON FUNCTION public.l2_distance(public.sparsevec, public.sparsevec) TO anon;
GRANT ALL ON FUNCTION public.l2_distance(public.sparsevec, public.sparsevec) TO authenticated;
GRANT ALL ON FUNCTION public.l2_distance(public.sparsevec, public.sparsevec) TO service_role;


--
-- Name: FUNCTION l2_distance(public.vector, public.vector); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.l2_distance(public.vector, public.vector) TO postgres;
GRANT ALL ON FUNCTION public.l2_distance(public.vector, public.vector) TO anon;
GRANT ALL ON FUNCTION public.l2_distance(public.vector, public.vector) TO authenticated;
GRANT ALL ON FUNCTION public.l2_distance(public.vector, public.vector) TO service_role;


--
-- Name: FUNCTION l2_norm(public.halfvec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.l2_norm(public.halfvec) TO postgres;
GRANT ALL ON FUNCTION public.l2_norm(public.halfvec) TO anon;
GRANT ALL ON FUNCTION public.l2_norm(public.halfvec) TO authenticated;
GRANT ALL ON FUNCTION public.l2_norm(public.halfvec) TO service_role;


--
-- Name: FUNCTION l2_norm(public.sparsevec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.l2_norm(public.sparsevec) TO postgres;
GRANT ALL ON FUNCTION public.l2_norm(public.sparsevec) TO anon;
GRANT ALL ON FUNCTION public.l2_norm(public.sparsevec) TO authenticated;
GRANT ALL ON FUNCTION public.l2_norm(public.sparsevec) TO service_role;


--
-- Name: FUNCTION l2_normalize(public.halfvec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.l2_normalize(public.halfvec) TO postgres;
GRANT ALL ON FUNCTION public.l2_normalize(public.halfvec) TO anon;
GRANT ALL ON FUNCTION public.l2_normalize(public.halfvec) TO authenticated;
GRANT ALL ON FUNCTION public.l2_normalize(public.halfvec) TO service_role;


--
-- Name: FUNCTION l2_normalize(public.sparsevec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.l2_normalize(public.sparsevec) TO postgres;
GRANT ALL ON FUNCTION public.l2_normalize(public.sparsevec) TO anon;
GRANT ALL ON FUNCTION public.l2_normalize(public.sparsevec) TO authenticated;
GRANT ALL ON FUNCTION public.l2_normalize(public.sparsevec) TO service_role;


--
-- Name: FUNCTION l2_normalize(public.vector); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.l2_normalize(public.vector) TO postgres;
GRANT ALL ON FUNCTION public.l2_normalize(public.vector) TO anon;
GRANT ALL ON FUNCTION public.l2_normalize(public.vector) TO authenticated;
GRANT ALL ON FUNCTION public.l2_normalize(public.vector) TO service_role;


--
-- Name: FUNCTION reset_icp_blocking_for_profile(profile_id uuid); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.reset_icp_blocking_for_profile(profile_id uuid) TO anon;
GRANT ALL ON FUNCTION public.reset_icp_blocking_for_profile(profile_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.reset_icp_blocking_for_profile(profile_id uuid) TO service_role;


--
-- Name: FUNCTION search_similar_content(query_embedding public.vector, organization_id text, similarity_threshold double precision, max_results integer); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.search_similar_content(query_embedding public.vector, organization_id text, similarity_threshold double precision, max_results integer) TO anon;
GRANT ALL ON FUNCTION public.search_similar_content(query_embedding public.vector, organization_id text, similarity_threshold double precision, max_results integer) TO authenticated;
GRANT ALL ON FUNCTION public.search_similar_content(query_embedding public.vector, organization_id text, similarity_threshold double precision, max_results integer) TO service_role;


--
-- Name: FUNCTION search_similar_content_text(query_embedding public.vector, organization_id text, similarity_threshold double precision, max_results integer); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.search_similar_content_text(query_embedding public.vector, organization_id text, similarity_threshold double precision, max_results integer) TO anon;
GRANT ALL ON FUNCTION public.search_similar_content_text(query_embedding public.vector, organization_id text, similarity_threshold double precision, max_results integer) TO authenticated;
GRANT ALL ON FUNCTION public.search_similar_content_text(query_embedding public.vector, organization_id text, similarity_threshold double precision, max_results integer) TO service_role;


--
-- Name: FUNCTION search_similar_content_uuid(query_embedding public.vector, organization_id uuid, similarity_threshold double precision, max_results integer); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.search_similar_content_uuid(query_embedding public.vector, organization_id uuid, similarity_threshold double precision, max_results integer) TO anon;
GRANT ALL ON FUNCTION public.search_similar_content_uuid(query_embedding public.vector, organization_id uuid, similarity_threshold double precision, max_results integer) TO authenticated;
GRANT ALL ON FUNCTION public.search_similar_content_uuid(query_embedding public.vector, organization_id uuid, similarity_threshold double precision, max_results integer) TO service_role;


--
-- Name: FUNCTION set_limit(real); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.set_limit(real) TO postgres;
GRANT ALL ON FUNCTION public.set_limit(real) TO anon;
GRANT ALL ON FUNCTION public.set_limit(real) TO authenticated;
GRANT ALL ON FUNCTION public.set_limit(real) TO service_role;


--
-- Name: FUNCTION set_task_priority_rank(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.set_task_priority_rank() TO anon;
GRANT ALL ON FUNCTION public.set_task_priority_rank() TO authenticated;
GRANT ALL ON FUNCTION public.set_task_priority_rank() TO service_role;


--
-- Name: FUNCTION show_limit(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.show_limit() TO postgres;
GRANT ALL ON FUNCTION public.show_limit() TO anon;
GRANT ALL ON FUNCTION public.show_limit() TO authenticated;
GRANT ALL ON FUNCTION public.show_limit() TO service_role;


--
-- Name: FUNCTION show_trgm(text); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.show_trgm(text) TO postgres;
GRANT ALL ON FUNCTION public.show_trgm(text) TO anon;
GRANT ALL ON FUNCTION public.show_trgm(text) TO authenticated;
GRANT ALL ON FUNCTION public.show_trgm(text) TO service_role;


--
-- Name: FUNCTION similarity(text, text); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.similarity(text, text) TO postgres;
GRANT ALL ON FUNCTION public.similarity(text, text) TO anon;
GRANT ALL ON FUNCTION public.similarity(text, text) TO authenticated;
GRANT ALL ON FUNCTION public.similarity(text, text) TO service_role;


--
-- Name: FUNCTION similarity_dist(text, text); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.similarity_dist(text, text) TO postgres;
GRANT ALL ON FUNCTION public.similarity_dist(text, text) TO anon;
GRANT ALL ON FUNCTION public.similarity_dist(text, text) TO authenticated;
GRANT ALL ON FUNCTION public.similarity_dist(text, text) TO service_role;


--
-- Name: FUNCTION similarity_op(text, text); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.similarity_op(text, text) TO postgres;
GRANT ALL ON FUNCTION public.similarity_op(text, text) TO anon;
GRANT ALL ON FUNCTION public.similarity_op(text, text) TO authenticated;
GRANT ALL ON FUNCTION public.similarity_op(text, text) TO service_role;


--
-- Name: FUNCTION sparsevec_cmp(public.sparsevec, public.sparsevec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.sparsevec_cmp(public.sparsevec, public.sparsevec) TO postgres;
GRANT ALL ON FUNCTION public.sparsevec_cmp(public.sparsevec, public.sparsevec) TO anon;
GRANT ALL ON FUNCTION public.sparsevec_cmp(public.sparsevec, public.sparsevec) TO authenticated;
GRANT ALL ON FUNCTION public.sparsevec_cmp(public.sparsevec, public.sparsevec) TO service_role;


--
-- Name: FUNCTION sparsevec_eq(public.sparsevec, public.sparsevec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.sparsevec_eq(public.sparsevec, public.sparsevec) TO postgres;
GRANT ALL ON FUNCTION public.sparsevec_eq(public.sparsevec, public.sparsevec) TO anon;
GRANT ALL ON FUNCTION public.sparsevec_eq(public.sparsevec, public.sparsevec) TO authenticated;
GRANT ALL ON FUNCTION public.sparsevec_eq(public.sparsevec, public.sparsevec) TO service_role;


--
-- Name: FUNCTION sparsevec_ge(public.sparsevec, public.sparsevec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.sparsevec_ge(public.sparsevec, public.sparsevec) TO postgres;
GRANT ALL ON FUNCTION public.sparsevec_ge(public.sparsevec, public.sparsevec) TO anon;
GRANT ALL ON FUNCTION public.sparsevec_ge(public.sparsevec, public.sparsevec) TO authenticated;
GRANT ALL ON FUNCTION public.sparsevec_ge(public.sparsevec, public.sparsevec) TO service_role;


--
-- Name: FUNCTION sparsevec_gt(public.sparsevec, public.sparsevec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.sparsevec_gt(public.sparsevec, public.sparsevec) TO postgres;
GRANT ALL ON FUNCTION public.sparsevec_gt(public.sparsevec, public.sparsevec) TO anon;
GRANT ALL ON FUNCTION public.sparsevec_gt(public.sparsevec, public.sparsevec) TO authenticated;
GRANT ALL ON FUNCTION public.sparsevec_gt(public.sparsevec, public.sparsevec) TO service_role;


--
-- Name: FUNCTION sparsevec_l2_squared_distance(public.sparsevec, public.sparsevec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.sparsevec_l2_squared_distance(public.sparsevec, public.sparsevec) TO postgres;
GRANT ALL ON FUNCTION public.sparsevec_l2_squared_distance(public.sparsevec, public.sparsevec) TO anon;
GRANT ALL ON FUNCTION public.sparsevec_l2_squared_distance(public.sparsevec, public.sparsevec) TO authenticated;
GRANT ALL ON FUNCTION public.sparsevec_l2_squared_distance(public.sparsevec, public.sparsevec) TO service_role;


--
-- Name: FUNCTION sparsevec_le(public.sparsevec, public.sparsevec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.sparsevec_le(public.sparsevec, public.sparsevec) TO postgres;
GRANT ALL ON FUNCTION public.sparsevec_le(public.sparsevec, public.sparsevec) TO anon;
GRANT ALL ON FUNCTION public.sparsevec_le(public.sparsevec, public.sparsevec) TO authenticated;
GRANT ALL ON FUNCTION public.sparsevec_le(public.sparsevec, public.sparsevec) TO service_role;


--
-- Name: FUNCTION sparsevec_lt(public.sparsevec, public.sparsevec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.sparsevec_lt(public.sparsevec, public.sparsevec) TO postgres;
GRANT ALL ON FUNCTION public.sparsevec_lt(public.sparsevec, public.sparsevec) TO anon;
GRANT ALL ON FUNCTION public.sparsevec_lt(public.sparsevec, public.sparsevec) TO authenticated;
GRANT ALL ON FUNCTION public.sparsevec_lt(public.sparsevec, public.sparsevec) TO service_role;


--
-- Name: FUNCTION sparsevec_ne(public.sparsevec, public.sparsevec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.sparsevec_ne(public.sparsevec, public.sparsevec) TO postgres;
GRANT ALL ON FUNCTION public.sparsevec_ne(public.sparsevec, public.sparsevec) TO anon;
GRANT ALL ON FUNCTION public.sparsevec_ne(public.sparsevec, public.sparsevec) TO authenticated;
GRANT ALL ON FUNCTION public.sparsevec_ne(public.sparsevec, public.sparsevec) TO service_role;


--
-- Name: FUNCTION sparsevec_negative_inner_product(public.sparsevec, public.sparsevec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.sparsevec_negative_inner_product(public.sparsevec, public.sparsevec) TO postgres;
GRANT ALL ON FUNCTION public.sparsevec_negative_inner_product(public.sparsevec, public.sparsevec) TO anon;
GRANT ALL ON FUNCTION public.sparsevec_negative_inner_product(public.sparsevec, public.sparsevec) TO authenticated;
GRANT ALL ON FUNCTION public.sparsevec_negative_inner_product(public.sparsevec, public.sparsevec) TO service_role;


--
-- Name: FUNCTION strict_word_similarity(text, text); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.strict_word_similarity(text, text) TO postgres;
GRANT ALL ON FUNCTION public.strict_word_similarity(text, text) TO anon;
GRANT ALL ON FUNCTION public.strict_word_similarity(text, text) TO authenticated;
GRANT ALL ON FUNCTION public.strict_word_similarity(text, text) TO service_role;


--
-- Name: FUNCTION strict_word_similarity_commutator_op(text, text); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.strict_word_similarity_commutator_op(text, text) TO postgres;
GRANT ALL ON FUNCTION public.strict_word_similarity_commutator_op(text, text) TO anon;
GRANT ALL ON FUNCTION public.strict_word_similarity_commutator_op(text, text) TO authenticated;
GRANT ALL ON FUNCTION public.strict_word_similarity_commutator_op(text, text) TO service_role;


--
-- Name: FUNCTION strict_word_similarity_dist_commutator_op(text, text); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.strict_word_similarity_dist_commutator_op(text, text) TO postgres;
GRANT ALL ON FUNCTION public.strict_word_similarity_dist_commutator_op(text, text) TO anon;
GRANT ALL ON FUNCTION public.strict_word_similarity_dist_commutator_op(text, text) TO authenticated;
GRANT ALL ON FUNCTION public.strict_word_similarity_dist_commutator_op(text, text) TO service_role;


--
-- Name: FUNCTION strict_word_similarity_dist_op(text, text); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.strict_word_similarity_dist_op(text, text) TO postgres;
GRANT ALL ON FUNCTION public.strict_word_similarity_dist_op(text, text) TO anon;
GRANT ALL ON FUNCTION public.strict_word_similarity_dist_op(text, text) TO authenticated;
GRANT ALL ON FUNCTION public.strict_word_similarity_dist_op(text, text) TO service_role;


--
-- Name: FUNCTION strict_word_similarity_op(text, text); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.strict_word_similarity_op(text, text) TO postgres;
GRANT ALL ON FUNCTION public.strict_word_similarity_op(text, text) TO anon;
GRANT ALL ON FUNCTION public.strict_word_similarity_op(text, text) TO authenticated;
GRANT ALL ON FUNCTION public.strict_word_similarity_op(text, text) TO service_role;


--
-- Name: FUNCTION subvector(public.halfvec, integer, integer); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.subvector(public.halfvec, integer, integer) TO postgres;
GRANT ALL ON FUNCTION public.subvector(public.halfvec, integer, integer) TO anon;
GRANT ALL ON FUNCTION public.subvector(public.halfvec, integer, integer) TO authenticated;
GRANT ALL ON FUNCTION public.subvector(public.halfvec, integer, integer) TO service_role;


--
-- Name: FUNCTION subvector(public.vector, integer, integer); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.subvector(public.vector, integer, integer) TO postgres;
GRANT ALL ON FUNCTION public.subvector(public.vector, integer, integer) TO anon;
GRANT ALL ON FUNCTION public.subvector(public.vector, integer, integer) TO authenticated;
GRANT ALL ON FUNCTION public.subvector(public.vector, integer, integer) TO service_role;


--
-- Name: FUNCTION update_company_blocked_status(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.update_company_blocked_status() TO anon;
GRANT ALL ON FUNCTION public.update_company_blocked_status() TO authenticated;
GRANT ALL ON FUNCTION public.update_company_blocked_status() TO service_role;


--
-- Name: FUNCTION update_organization_settings_updated_at(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.update_organization_settings_updated_at() TO anon;
GRANT ALL ON FUNCTION public.update_organization_settings_updated_at() TO authenticated;
GRANT ALL ON FUNCTION public.update_organization_settings_updated_at() TO service_role;


--
-- Name: FUNCTION update_style_guidelines(org_id text, tone jsonb, keywords jsonb, style jsonb, narratives jsonb); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.update_style_guidelines(org_id text, tone jsonb, keywords jsonb, style jsonb, narratives jsonb) TO anon;
GRANT ALL ON FUNCTION public.update_style_guidelines(org_id text, tone jsonb, keywords jsonb, style jsonb, narratives jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.update_style_guidelines(org_id text, tone jsonb, keywords jsonb, style jsonb, narratives jsonb) TO service_role;


--
-- Name: FUNCTION update_token_usage_summary(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.update_token_usage_summary() TO anon;
GRANT ALL ON FUNCTION public.update_token_usage_summary() TO authenticated;
GRANT ALL ON FUNCTION public.update_token_usage_summary() TO service_role;


--
-- Name: FUNCTION update_updated_at_column(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.update_updated_at_column() TO anon;
GRANT ALL ON FUNCTION public.update_updated_at_column() TO authenticated;
GRANT ALL ON FUNCTION public.update_updated_at_column() TO service_role;


--
-- Name: FUNCTION vector_accum(double precision[], public.vector); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.vector_accum(double precision[], public.vector) TO postgres;
GRANT ALL ON FUNCTION public.vector_accum(double precision[], public.vector) TO anon;
GRANT ALL ON FUNCTION public.vector_accum(double precision[], public.vector) TO authenticated;
GRANT ALL ON FUNCTION public.vector_accum(double precision[], public.vector) TO service_role;


--
-- Name: FUNCTION vector_add(public.vector, public.vector); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.vector_add(public.vector, public.vector) TO postgres;
GRANT ALL ON FUNCTION public.vector_add(public.vector, public.vector) TO anon;
GRANT ALL ON FUNCTION public.vector_add(public.vector, public.vector) TO authenticated;
GRANT ALL ON FUNCTION public.vector_add(public.vector, public.vector) TO service_role;


--
-- Name: FUNCTION vector_avg(double precision[]); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.vector_avg(double precision[]) TO postgres;
GRANT ALL ON FUNCTION public.vector_avg(double precision[]) TO anon;
GRANT ALL ON FUNCTION public.vector_avg(double precision[]) TO authenticated;
GRANT ALL ON FUNCTION public.vector_avg(double precision[]) TO service_role;


--
-- Name: FUNCTION vector_cmp(public.vector, public.vector); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.vector_cmp(public.vector, public.vector) TO postgres;
GRANT ALL ON FUNCTION public.vector_cmp(public.vector, public.vector) TO anon;
GRANT ALL ON FUNCTION public.vector_cmp(public.vector, public.vector) TO authenticated;
GRANT ALL ON FUNCTION public.vector_cmp(public.vector, public.vector) TO service_role;


--
-- Name: FUNCTION vector_combine(double precision[], double precision[]); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.vector_combine(double precision[], double precision[]) TO postgres;
GRANT ALL ON FUNCTION public.vector_combine(double precision[], double precision[]) TO anon;
GRANT ALL ON FUNCTION public.vector_combine(double precision[], double precision[]) TO authenticated;
GRANT ALL ON FUNCTION public.vector_combine(double precision[], double precision[]) TO service_role;


--
-- Name: FUNCTION vector_concat(public.vector, public.vector); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.vector_concat(public.vector, public.vector) TO postgres;
GRANT ALL ON FUNCTION public.vector_concat(public.vector, public.vector) TO anon;
GRANT ALL ON FUNCTION public.vector_concat(public.vector, public.vector) TO authenticated;
GRANT ALL ON FUNCTION public.vector_concat(public.vector, public.vector) TO service_role;


--
-- Name: FUNCTION vector_dims(public.halfvec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.vector_dims(public.halfvec) TO postgres;
GRANT ALL ON FUNCTION public.vector_dims(public.halfvec) TO anon;
GRANT ALL ON FUNCTION public.vector_dims(public.halfvec) TO authenticated;
GRANT ALL ON FUNCTION public.vector_dims(public.halfvec) TO service_role;


--
-- Name: FUNCTION vector_dims(public.vector); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.vector_dims(public.vector) TO postgres;
GRANT ALL ON FUNCTION public.vector_dims(public.vector) TO anon;
GRANT ALL ON FUNCTION public.vector_dims(public.vector) TO authenticated;
GRANT ALL ON FUNCTION public.vector_dims(public.vector) TO service_role;


--
-- Name: FUNCTION vector_eq(public.vector, public.vector); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.vector_eq(public.vector, public.vector) TO postgres;
GRANT ALL ON FUNCTION public.vector_eq(public.vector, public.vector) TO anon;
GRANT ALL ON FUNCTION public.vector_eq(public.vector, public.vector) TO authenticated;
GRANT ALL ON FUNCTION public.vector_eq(public.vector, public.vector) TO service_role;


--
-- Name: FUNCTION vector_ge(public.vector, public.vector); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.vector_ge(public.vector, public.vector) TO postgres;
GRANT ALL ON FUNCTION public.vector_ge(public.vector, public.vector) TO anon;
GRANT ALL ON FUNCTION public.vector_ge(public.vector, public.vector) TO authenticated;
GRANT ALL ON FUNCTION public.vector_ge(public.vector, public.vector) TO service_role;


--
-- Name: FUNCTION vector_gt(public.vector, public.vector); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.vector_gt(public.vector, public.vector) TO postgres;
GRANT ALL ON FUNCTION public.vector_gt(public.vector, public.vector) TO anon;
GRANT ALL ON FUNCTION public.vector_gt(public.vector, public.vector) TO authenticated;
GRANT ALL ON FUNCTION public.vector_gt(public.vector, public.vector) TO service_role;


--
-- Name: FUNCTION vector_l2_squared_distance(public.vector, public.vector); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.vector_l2_squared_distance(public.vector, public.vector) TO postgres;
GRANT ALL ON FUNCTION public.vector_l2_squared_distance(public.vector, public.vector) TO anon;
GRANT ALL ON FUNCTION public.vector_l2_squared_distance(public.vector, public.vector) TO authenticated;
GRANT ALL ON FUNCTION public.vector_l2_squared_distance(public.vector, public.vector) TO service_role;


--
-- Name: FUNCTION vector_le(public.vector, public.vector); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.vector_le(public.vector, public.vector) TO postgres;
GRANT ALL ON FUNCTION public.vector_le(public.vector, public.vector) TO anon;
GRANT ALL ON FUNCTION public.vector_le(public.vector, public.vector) TO authenticated;
GRANT ALL ON FUNCTION public.vector_le(public.vector, public.vector) TO service_role;


--
-- Name: FUNCTION vector_lt(public.vector, public.vector); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.vector_lt(public.vector, public.vector) TO postgres;
GRANT ALL ON FUNCTION public.vector_lt(public.vector, public.vector) TO anon;
GRANT ALL ON FUNCTION public.vector_lt(public.vector, public.vector) TO authenticated;
GRANT ALL ON FUNCTION public.vector_lt(public.vector, public.vector) TO service_role;


--
-- Name: FUNCTION vector_mul(public.vector, public.vector); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.vector_mul(public.vector, public.vector) TO postgres;
GRANT ALL ON FUNCTION public.vector_mul(public.vector, public.vector) TO anon;
GRANT ALL ON FUNCTION public.vector_mul(public.vector, public.vector) TO authenticated;
GRANT ALL ON FUNCTION public.vector_mul(public.vector, public.vector) TO service_role;


--
-- Name: FUNCTION vector_ne(public.vector, public.vector); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.vector_ne(public.vector, public.vector) TO postgres;
GRANT ALL ON FUNCTION public.vector_ne(public.vector, public.vector) TO anon;
GRANT ALL ON FUNCTION public.vector_ne(public.vector, public.vector) TO authenticated;
GRANT ALL ON FUNCTION public.vector_ne(public.vector, public.vector) TO service_role;


--
-- Name: FUNCTION vector_negative_inner_product(public.vector, public.vector); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.vector_negative_inner_product(public.vector, public.vector) TO postgres;
GRANT ALL ON FUNCTION public.vector_negative_inner_product(public.vector, public.vector) TO anon;
GRANT ALL ON FUNCTION public.vector_negative_inner_product(public.vector, public.vector) TO authenticated;
GRANT ALL ON FUNCTION public.vector_negative_inner_product(public.vector, public.vector) TO service_role;


--
-- Name: FUNCTION vector_norm(public.vector); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.vector_norm(public.vector) TO postgres;
GRANT ALL ON FUNCTION public.vector_norm(public.vector) TO anon;
GRANT ALL ON FUNCTION public.vector_norm(public.vector) TO authenticated;
GRANT ALL ON FUNCTION public.vector_norm(public.vector) TO service_role;


--
-- Name: FUNCTION vector_spherical_distance(public.vector, public.vector); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.vector_spherical_distance(public.vector, public.vector) TO postgres;
GRANT ALL ON FUNCTION public.vector_spherical_distance(public.vector, public.vector) TO anon;
GRANT ALL ON FUNCTION public.vector_spherical_distance(public.vector, public.vector) TO authenticated;
GRANT ALL ON FUNCTION public.vector_spherical_distance(public.vector, public.vector) TO service_role;


--
-- Name: FUNCTION vector_sub(public.vector, public.vector); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.vector_sub(public.vector, public.vector) TO postgres;
GRANT ALL ON FUNCTION public.vector_sub(public.vector, public.vector) TO anon;
GRANT ALL ON FUNCTION public.vector_sub(public.vector, public.vector) TO authenticated;
GRANT ALL ON FUNCTION public.vector_sub(public.vector, public.vector) TO service_role;


--
-- Name: FUNCTION word_similarity(text, text); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.word_similarity(text, text) TO postgres;
GRANT ALL ON FUNCTION public.word_similarity(text, text) TO anon;
GRANT ALL ON FUNCTION public.word_similarity(text, text) TO authenticated;
GRANT ALL ON FUNCTION public.word_similarity(text, text) TO service_role;


--
-- Name: FUNCTION word_similarity_commutator_op(text, text); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.word_similarity_commutator_op(text, text) TO postgres;
GRANT ALL ON FUNCTION public.word_similarity_commutator_op(text, text) TO anon;
GRANT ALL ON FUNCTION public.word_similarity_commutator_op(text, text) TO authenticated;
GRANT ALL ON FUNCTION public.word_similarity_commutator_op(text, text) TO service_role;


--
-- Name: FUNCTION word_similarity_dist_commutator_op(text, text); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.word_similarity_dist_commutator_op(text, text) TO postgres;
GRANT ALL ON FUNCTION public.word_similarity_dist_commutator_op(text, text) TO anon;
GRANT ALL ON FUNCTION public.word_similarity_dist_commutator_op(text, text) TO authenticated;
GRANT ALL ON FUNCTION public.word_similarity_dist_commutator_op(text, text) TO service_role;


--
-- Name: FUNCTION word_similarity_dist_op(text, text); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.word_similarity_dist_op(text, text) TO postgres;
GRANT ALL ON FUNCTION public.word_similarity_dist_op(text, text) TO anon;
GRANT ALL ON FUNCTION public.word_similarity_dist_op(text, text) TO authenticated;
GRANT ALL ON FUNCTION public.word_similarity_dist_op(text, text) TO service_role;


--
-- Name: FUNCTION word_similarity_op(text, text); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.word_similarity_op(text, text) TO postgres;
GRANT ALL ON FUNCTION public.word_similarity_op(text, text) TO anon;
GRANT ALL ON FUNCTION public.word_similarity_op(text, text) TO authenticated;
GRANT ALL ON FUNCTION public.word_similarity_op(text, text) TO service_role;


--
-- Name: FUNCTION apply_rls(wal jsonb, max_record_bytes integer); Type: ACL; Schema: realtime; Owner: supabase_admin
--

GRANT ALL ON FUNCTION realtime.apply_rls(wal jsonb, max_record_bytes integer) TO postgres;
GRANT ALL ON FUNCTION realtime.apply_rls(wal jsonb, max_record_bytes integer) TO dashboard_user;
GRANT ALL ON FUNCTION realtime.apply_rls(wal jsonb, max_record_bytes integer) TO anon;
GRANT ALL ON FUNCTION realtime.apply_rls(wal jsonb, max_record_bytes integer) TO authenticated;
GRANT ALL ON FUNCTION realtime.apply_rls(wal jsonb, max_record_bytes integer) TO service_role;
GRANT ALL ON FUNCTION realtime.apply_rls(wal jsonb, max_record_bytes integer) TO supabase_realtime_admin;


--
-- Name: FUNCTION broadcast_changes(topic_name text, event_name text, operation text, table_name text, table_schema text, new record, old record, level text); Type: ACL; Schema: realtime; Owner: supabase_admin
--

GRANT ALL ON FUNCTION realtime.broadcast_changes(topic_name text, event_name text, operation text, table_name text, table_schema text, new record, old record, level text) TO postgres;
GRANT ALL ON FUNCTION realtime.broadcast_changes(topic_name text, event_name text, operation text, table_name text, table_schema text, new record, old record, level text) TO dashboard_user;


--
-- Name: FUNCTION build_prepared_statement_sql(prepared_statement_name text, entity regclass, columns realtime.wal_column[]); Type: ACL; Schema: realtime; Owner: supabase_admin
--

GRANT ALL ON FUNCTION realtime.build_prepared_statement_sql(prepared_statement_name text, entity regclass, columns realtime.wal_column[]) TO postgres;
GRANT ALL ON FUNCTION realtime.build_prepared_statement_sql(prepared_statement_name text, entity regclass, columns realtime.wal_column[]) TO dashboard_user;
GRANT ALL ON FUNCTION realtime.build_prepared_statement_sql(prepared_statement_name text, entity regclass, columns realtime.wal_column[]) TO anon;
GRANT ALL ON FUNCTION realtime.build_prepared_statement_sql(prepared_statement_name text, entity regclass, columns realtime.wal_column[]) TO authenticated;
GRANT ALL ON FUNCTION realtime.build_prepared_statement_sql(prepared_statement_name text, entity regclass, columns realtime.wal_column[]) TO service_role;
GRANT ALL ON FUNCTION realtime.build_prepared_statement_sql(prepared_statement_name text, entity regclass, columns realtime.wal_column[]) TO supabase_realtime_admin;


--
-- Name: FUNCTION "cast"(val text, type_ regtype); Type: ACL; Schema: realtime; Owner: supabase_admin
--

GRANT ALL ON FUNCTION realtime."cast"(val text, type_ regtype) TO postgres;
GRANT ALL ON FUNCTION realtime."cast"(val text, type_ regtype) TO dashboard_user;
GRANT ALL ON FUNCTION realtime."cast"(val text, type_ regtype) TO anon;
GRANT ALL ON FUNCTION realtime."cast"(val text, type_ regtype) TO authenticated;
GRANT ALL ON FUNCTION realtime."cast"(val text, type_ regtype) TO service_role;
GRANT ALL ON FUNCTION realtime."cast"(val text, type_ regtype) TO supabase_realtime_admin;


--
-- Name: FUNCTION check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text); Type: ACL; Schema: realtime; Owner: supabase_admin
--

GRANT ALL ON FUNCTION realtime.check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text) TO postgres;
GRANT ALL ON FUNCTION realtime.check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text) TO dashboard_user;
GRANT ALL ON FUNCTION realtime.check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text) TO anon;
GRANT ALL ON FUNCTION realtime.check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text) TO authenticated;
GRANT ALL ON FUNCTION realtime.check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text) TO service_role;
GRANT ALL ON FUNCTION realtime.check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text) TO supabase_realtime_admin;


--
-- Name: FUNCTION is_visible_through_filters(columns realtime.wal_column[], filters realtime.user_defined_filter[]); Type: ACL; Schema: realtime; Owner: supabase_admin
--

GRANT ALL ON FUNCTION realtime.is_visible_through_filters(columns realtime.wal_column[], filters realtime.user_defined_filter[]) TO postgres;
GRANT ALL ON FUNCTION realtime.is_visible_through_filters(columns realtime.wal_column[], filters realtime.user_defined_filter[]) TO dashboard_user;
GRANT ALL ON FUNCTION realtime.is_visible_through_filters(columns realtime.wal_column[], filters realtime.user_defined_filter[]) TO anon;
GRANT ALL ON FUNCTION realtime.is_visible_through_filters(columns realtime.wal_column[], filters realtime.user_defined_filter[]) TO authenticated;
GRANT ALL ON FUNCTION realtime.is_visible_through_filters(columns realtime.wal_column[], filters realtime.user_defined_filter[]) TO service_role;
GRANT ALL ON FUNCTION realtime.is_visible_through_filters(columns realtime.wal_column[], filters realtime.user_defined_filter[]) TO supabase_realtime_admin;


--
-- Name: FUNCTION list_changes(publication name, slot_name name, max_changes integer, max_record_bytes integer); Type: ACL; Schema: realtime; Owner: supabase_admin
--

GRANT ALL ON FUNCTION realtime.list_changes(publication name, slot_name name, max_changes integer, max_record_bytes integer) TO postgres;
GRANT ALL ON FUNCTION realtime.list_changes(publication name, slot_name name, max_changes integer, max_record_bytes integer) TO dashboard_user;
GRANT ALL ON FUNCTION realtime.list_changes(publication name, slot_name name, max_changes integer, max_record_bytes integer) TO anon;
GRANT ALL ON FUNCTION realtime.list_changes(publication name, slot_name name, max_changes integer, max_record_bytes integer) TO authenticated;
GRANT ALL ON FUNCTION realtime.list_changes(publication name, slot_name name, max_changes integer, max_record_bytes integer) TO service_role;
GRANT ALL ON FUNCTION realtime.list_changes(publication name, slot_name name, max_changes integer, max_record_bytes integer) TO supabase_realtime_admin;


--
-- Name: FUNCTION quote_wal2json(entity regclass); Type: ACL; Schema: realtime; Owner: supabase_admin
--

GRANT ALL ON FUNCTION realtime.quote_wal2json(entity regclass) TO postgres;
GRANT ALL ON FUNCTION realtime.quote_wal2json(entity regclass) TO dashboard_user;
GRANT ALL ON FUNCTION realtime.quote_wal2json(entity regclass) TO anon;
GRANT ALL ON FUNCTION realtime.quote_wal2json(entity regclass) TO authenticated;
GRANT ALL ON FUNCTION realtime.quote_wal2json(entity regclass) TO service_role;
GRANT ALL ON FUNCTION realtime.quote_wal2json(entity regclass) TO supabase_realtime_admin;


--
-- Name: FUNCTION send(payload jsonb, event text, topic text, private boolean); Type: ACL; Schema: realtime; Owner: supabase_admin
--

GRANT ALL ON FUNCTION realtime.send(payload jsonb, event text, topic text, private boolean) TO postgres;
GRANT ALL ON FUNCTION realtime.send(payload jsonb, event text, topic text, private boolean) TO dashboard_user;


--
-- Name: FUNCTION subscription_check_filters(); Type: ACL; Schema: realtime; Owner: supabase_admin
--

GRANT ALL ON FUNCTION realtime.subscription_check_filters() TO postgres;
GRANT ALL ON FUNCTION realtime.subscription_check_filters() TO dashboard_user;
GRANT ALL ON FUNCTION realtime.subscription_check_filters() TO anon;
GRANT ALL ON FUNCTION realtime.subscription_check_filters() TO authenticated;
GRANT ALL ON FUNCTION realtime.subscription_check_filters() TO service_role;
GRANT ALL ON FUNCTION realtime.subscription_check_filters() TO supabase_realtime_admin;


--
-- Name: FUNCTION to_regrole(role_name text); Type: ACL; Schema: realtime; Owner: supabase_admin
--

GRANT ALL ON FUNCTION realtime.to_regrole(role_name text) TO postgres;
GRANT ALL ON FUNCTION realtime.to_regrole(role_name text) TO dashboard_user;
GRANT ALL ON FUNCTION realtime.to_regrole(role_name text) TO anon;
GRANT ALL ON FUNCTION realtime.to_regrole(role_name text) TO authenticated;
GRANT ALL ON FUNCTION realtime.to_regrole(role_name text) TO service_role;
GRANT ALL ON FUNCTION realtime.to_regrole(role_name text) TO supabase_realtime_admin;


--
-- Name: FUNCTION topic(); Type: ACL; Schema: realtime; Owner: supabase_realtime_admin
--

GRANT ALL ON FUNCTION realtime.topic() TO postgres;
GRANT ALL ON FUNCTION realtime.topic() TO dashboard_user;


--
-- Name: FUNCTION can_insert_object(bucketid text, name text, owner uuid, metadata jsonb); Type: ACL; Schema: storage; Owner: supabase_storage_admin
--

GRANT ALL ON FUNCTION storage.can_insert_object(bucketid text, name text, owner uuid, metadata jsonb) TO postgres;


--
-- Name: FUNCTION delete_leaf_prefixes(bucket_ids text[], names text[]); Type: ACL; Schema: storage; Owner: supabase_storage_admin
--

GRANT ALL ON FUNCTION storage.delete_leaf_prefixes(bucket_ids text[], names text[]) TO postgres;


--
-- Name: FUNCTION enforce_bucket_name_length(); Type: ACL; Schema: storage; Owner: supabase_storage_admin
--

GRANT ALL ON FUNCTION storage.enforce_bucket_name_length() TO postgres;


--
-- Name: FUNCTION extension(name text); Type: ACL; Schema: storage; Owner: supabase_storage_admin
--

GRANT ALL ON FUNCTION storage.extension(name text) TO postgres;


--
-- Name: FUNCTION filename(name text); Type: ACL; Schema: storage; Owner: supabase_storage_admin
--

GRANT ALL ON FUNCTION storage.filename(name text) TO postgres;


--
-- Name: FUNCTION foldername(name text); Type: ACL; Schema: storage; Owner: supabase_storage_admin
--

GRANT ALL ON FUNCTION storage.foldername(name text) TO postgres;


--
-- Name: FUNCTION get_level(name text); Type: ACL; Schema: storage; Owner: supabase_storage_admin
--

GRANT ALL ON FUNCTION storage.get_level(name text) TO postgres;


--
-- Name: FUNCTION get_prefix(name text); Type: ACL; Schema: storage; Owner: supabase_storage_admin
--

GRANT ALL ON FUNCTION storage.get_prefix(name text) TO postgres;


--
-- Name: FUNCTION get_prefixes(name text); Type: ACL; Schema: storage; Owner: supabase_storage_admin
--

GRANT ALL ON FUNCTION storage.get_prefixes(name text) TO postgres;


--
-- Name: FUNCTION get_size_by_bucket(); Type: ACL; Schema: storage; Owner: supabase_storage_admin
--

GRANT ALL ON FUNCTION storage.get_size_by_bucket() TO postgres;


--
-- Name: FUNCTION list_multipart_uploads_with_delimiter(bucket_id text, prefix_param text, delimiter_param text, max_keys integer, next_key_token text, next_upload_token text); Type: ACL; Schema: storage; Owner: supabase_storage_admin
--

GRANT ALL ON FUNCTION storage.list_multipart_uploads_with_delimiter(bucket_id text, prefix_param text, delimiter_param text, max_keys integer, next_key_token text, next_upload_token text) TO postgres;


--
-- Name: FUNCTION operation(); Type: ACL; Schema: storage; Owner: supabase_storage_admin
--

GRANT ALL ON FUNCTION storage.operation() TO postgres;


--
-- Name: FUNCTION search(prefix text, bucketname text, limits integer, levels integer, offsets integer, search text, sortcolumn text, sortorder text); Type: ACL; Schema: storage; Owner: supabase_storage_admin
--

GRANT ALL ON FUNCTION storage.search(prefix text, bucketname text, limits integer, levels integer, offsets integer, search text, sortcolumn text, sortorder text) TO postgres;


--
-- Name: FUNCTION search_legacy_v1(prefix text, bucketname text, limits integer, levels integer, offsets integer, search text, sortcolumn text, sortorder text); Type: ACL; Schema: storage; Owner: supabase_storage_admin
--

GRANT ALL ON FUNCTION storage.search_legacy_v1(prefix text, bucketname text, limits integer, levels integer, offsets integer, search text, sortcolumn text, sortorder text) TO postgres;


--
-- Name: FUNCTION search_v2(prefix text, bucket_name text, limits integer, levels integer, start_after text, sort_order text, sort_column text, sort_column_after text); Type: ACL; Schema: storage; Owner: supabase_storage_admin
--

GRANT ALL ON FUNCTION storage.search_v2(prefix text, bucket_name text, limits integer, levels integer, start_after text, sort_order text, sort_column text, sort_column_after text) TO postgres;


--
-- Name: FUNCTION update_updated_at_column(); Type: ACL; Schema: storage; Owner: supabase_storage_admin
--

GRANT ALL ON FUNCTION storage.update_updated_at_column() TO postgres;


--
-- Name: FUNCTION _crypto_aead_det_decrypt(message bytea, additional bytea, key_id bigint, context bytea, nonce bytea); Type: ACL; Schema: vault; Owner: supabase_admin
--

GRANT ALL ON FUNCTION vault._crypto_aead_det_decrypt(message bytea, additional bytea, key_id bigint, context bytea, nonce bytea) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION vault._crypto_aead_det_decrypt(message bytea, additional bytea, key_id bigint, context bytea, nonce bytea) TO service_role;


--
-- Name: FUNCTION create_secret(new_secret text, new_name text, new_description text, new_key_id uuid); Type: ACL; Schema: vault; Owner: supabase_admin
--

GRANT ALL ON FUNCTION vault.create_secret(new_secret text, new_name text, new_description text, new_key_id uuid) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION vault.create_secret(new_secret text, new_name text, new_description text, new_key_id uuid) TO service_role;


--
-- Name: FUNCTION update_secret(secret_id uuid, new_secret text, new_name text, new_description text, new_key_id uuid); Type: ACL; Schema: vault; Owner: supabase_admin
--

GRANT ALL ON FUNCTION vault.update_secret(secret_id uuid, new_secret text, new_name text, new_description text, new_key_id uuid) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION vault.update_secret(secret_id uuid, new_secret text, new_name text, new_description text, new_key_id uuid) TO service_role;


--
-- Name: FUNCTION avg(public.halfvec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.avg(public.halfvec) TO postgres;
GRANT ALL ON FUNCTION public.avg(public.halfvec) TO anon;
GRANT ALL ON FUNCTION public.avg(public.halfvec) TO authenticated;
GRANT ALL ON FUNCTION public.avg(public.halfvec) TO service_role;


--
-- Name: FUNCTION avg(public.vector); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.avg(public.vector) TO postgres;
GRANT ALL ON FUNCTION public.avg(public.vector) TO anon;
GRANT ALL ON FUNCTION public.avg(public.vector) TO authenticated;
GRANT ALL ON FUNCTION public.avg(public.vector) TO service_role;


--
-- Name: FUNCTION sum(public.halfvec); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.sum(public.halfvec) TO postgres;
GRANT ALL ON FUNCTION public.sum(public.halfvec) TO anon;
GRANT ALL ON FUNCTION public.sum(public.halfvec) TO authenticated;
GRANT ALL ON FUNCTION public.sum(public.halfvec) TO service_role;


--
-- Name: FUNCTION sum(public.vector); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.sum(public.vector) TO postgres;
GRANT ALL ON FUNCTION public.sum(public.vector) TO anon;
GRANT ALL ON FUNCTION public.sum(public.vector) TO authenticated;
GRANT ALL ON FUNCTION public.sum(public.vector) TO service_role;


--
-- Name: TABLE audit_log_entries; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT ALL ON TABLE auth.audit_log_entries TO dashboard_user;
GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.audit_log_entries TO postgres;
GRANT SELECT ON TABLE auth.audit_log_entries TO postgres WITH GRANT OPTION;


--
-- Name: TABLE flow_state; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.flow_state TO postgres;
GRANT SELECT ON TABLE auth.flow_state TO postgres WITH GRANT OPTION;
GRANT ALL ON TABLE auth.flow_state TO dashboard_user;


--
-- Name: TABLE identities; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.identities TO postgres;
GRANT SELECT ON TABLE auth.identities TO postgres WITH GRANT OPTION;
GRANT ALL ON TABLE auth.identities TO dashboard_user;


--
-- Name: TABLE instances; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT ALL ON TABLE auth.instances TO dashboard_user;
GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.instances TO postgres;
GRANT SELECT ON TABLE auth.instances TO postgres WITH GRANT OPTION;


--
-- Name: TABLE mfa_amr_claims; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.mfa_amr_claims TO postgres;
GRANT SELECT ON TABLE auth.mfa_amr_claims TO postgres WITH GRANT OPTION;
GRANT ALL ON TABLE auth.mfa_amr_claims TO dashboard_user;


--
-- Name: TABLE mfa_challenges; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.mfa_challenges TO postgres;
GRANT SELECT ON TABLE auth.mfa_challenges TO postgres WITH GRANT OPTION;
GRANT ALL ON TABLE auth.mfa_challenges TO dashboard_user;


--
-- Name: TABLE mfa_factors; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.mfa_factors TO postgres;
GRANT SELECT ON TABLE auth.mfa_factors TO postgres WITH GRANT OPTION;
GRANT ALL ON TABLE auth.mfa_factors TO dashboard_user;


--
-- Name: TABLE oauth_authorizations; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT ALL ON TABLE auth.oauth_authorizations TO postgres;
GRANT ALL ON TABLE auth.oauth_authorizations TO dashboard_user;


--
-- Name: TABLE oauth_client_states; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT ALL ON TABLE auth.oauth_client_states TO postgres;
GRANT ALL ON TABLE auth.oauth_client_states TO dashboard_user;


--
-- Name: TABLE oauth_clients; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT ALL ON TABLE auth.oauth_clients TO postgres;
GRANT ALL ON TABLE auth.oauth_clients TO dashboard_user;


--
-- Name: TABLE oauth_consents; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT ALL ON TABLE auth.oauth_consents TO postgres;
GRANT ALL ON TABLE auth.oauth_consents TO dashboard_user;


--
-- Name: TABLE one_time_tokens; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.one_time_tokens TO postgres;
GRANT SELECT ON TABLE auth.one_time_tokens TO postgres WITH GRANT OPTION;
GRANT ALL ON TABLE auth.one_time_tokens TO dashboard_user;


--
-- Name: TABLE refresh_tokens; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT ALL ON TABLE auth.refresh_tokens TO dashboard_user;
GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.refresh_tokens TO postgres;
GRANT SELECT ON TABLE auth.refresh_tokens TO postgres WITH GRANT OPTION;


--
-- Name: SEQUENCE refresh_tokens_id_seq; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT ALL ON SEQUENCE auth.refresh_tokens_id_seq TO dashboard_user;
GRANT ALL ON SEQUENCE auth.refresh_tokens_id_seq TO postgres;


--
-- Name: TABLE saml_providers; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.saml_providers TO postgres;
GRANT SELECT ON TABLE auth.saml_providers TO postgres WITH GRANT OPTION;
GRANT ALL ON TABLE auth.saml_providers TO dashboard_user;


--
-- Name: TABLE saml_relay_states; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.saml_relay_states TO postgres;
GRANT SELECT ON TABLE auth.saml_relay_states TO postgres WITH GRANT OPTION;
GRANT ALL ON TABLE auth.saml_relay_states TO dashboard_user;


--
-- Name: TABLE sessions; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.sessions TO postgres;
GRANT SELECT ON TABLE auth.sessions TO postgres WITH GRANT OPTION;
GRANT ALL ON TABLE auth.sessions TO dashboard_user;


--
-- Name: TABLE sso_domains; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.sso_domains TO postgres;
GRANT SELECT ON TABLE auth.sso_domains TO postgres WITH GRANT OPTION;
GRANT ALL ON TABLE auth.sso_domains TO dashboard_user;


--
-- Name: TABLE sso_providers; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.sso_providers TO postgres;
GRANT SELECT ON TABLE auth.sso_providers TO postgres WITH GRANT OPTION;
GRANT ALL ON TABLE auth.sso_providers TO dashboard_user;


--
-- Name: TABLE users; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT ALL ON TABLE auth.users TO dashboard_user;
GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.users TO postgres;
GRANT SELECT ON TABLE auth.users TO postgres WITH GRANT OPTION;


--
-- Name: TABLE pg_stat_statements; Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON TABLE extensions.pg_stat_statements TO postgres WITH GRANT OPTION;
GRANT ALL ON TABLE extensions.pg_stat_statements TO dashboard_user;


--
-- Name: TABLE pg_stat_statements_info; Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON TABLE extensions.pg_stat_statements_info TO postgres WITH GRANT OPTION;
GRANT ALL ON TABLE extensions.pg_stat_statements_info TO dashboard_user;


--
-- Name: TABLE campaign_activities; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.campaign_activities TO anon;
GRANT ALL ON TABLE public.campaign_activities TO authenticated;
GRANT ALL ON TABLE public.campaign_activities TO service_role;


--
-- Name: TABLE campaign_companies; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.campaign_companies TO anon;
GRANT ALL ON TABLE public.campaign_companies TO authenticated;
GRANT ALL ON TABLE public.campaign_companies TO service_role;


--
-- Name: TABLE campaign_emails; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.campaign_emails TO anon;
GRANT ALL ON TABLE public.campaign_emails TO authenticated;
GRANT ALL ON TABLE public.campaign_emails TO service_role;


--
-- Name: TABLE campaign_files; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.campaign_files TO anon;
GRANT ALL ON TABLE public.campaign_files TO authenticated;
GRANT ALL ON TABLE public.campaign_files TO service_role;


--
-- Name: TABLE campaign_seed_companies; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.campaign_seed_companies TO anon;
GRANT ALL ON TABLE public.campaign_seed_companies TO authenticated;
GRANT ALL ON TABLE public.campaign_seed_companies TO service_role;


--
-- Name: TABLE campaigns; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.campaigns TO anon;
GRANT ALL ON TABLE public.campaigns TO authenticated;
GRANT ALL ON TABLE public.campaigns TO service_role;


--
-- Name: TABLE companies; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.companies TO anon;
GRANT ALL ON TABLE public.companies TO authenticated;
GRANT ALL ON TABLE public.companies TO service_role;


--
-- Name: TABLE company_activities; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.company_activities TO anon;
GRANT ALL ON TABLE public.company_activities TO authenticated;
GRANT ALL ON TABLE public.company_activities TO service_role;


--
-- Name: TABLE company_contacts; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.company_contacts TO anon;
GRANT ALL ON TABLE public.company_contacts TO authenticated;
GRANT ALL ON TABLE public.company_contacts TO service_role;


--
-- Name: TABLE company_research_jobs; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.company_research_jobs TO anon;
GRANT ALL ON TABLE public.company_research_jobs TO authenticated;
GRANT ALL ON TABLE public.company_research_jobs TO service_role;


--
-- Name: TABLE contact_activities; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.contact_activities TO anon;
GRANT ALL ON TABLE public.contact_activities TO authenticated;
GRANT ALL ON TABLE public.contact_activities TO service_role;


--
-- Name: TABLE contact_channels; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.contact_channels TO anon;
GRANT ALL ON TABLE public.contact_channels TO authenticated;
GRANT ALL ON TABLE public.contact_channels TO service_role;


--
-- Name: TABLE contact_notes; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.contact_notes TO anon;
GRANT ALL ON TABLE public.contact_notes TO authenticated;
GRANT ALL ON TABLE public.contact_notes TO service_role;


--
-- Name: TABLE contacts; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.contacts TO anon;
GRANT ALL ON TABLE public.contacts TO authenticated;
GRANT ALL ON TABLE public.contacts TO service_role;


--
-- Name: TABLE conversation_messages; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.conversation_messages TO anon;
GRANT ALL ON TABLE public.conversation_messages TO authenticated;
GRANT ALL ON TABLE public.conversation_messages TO service_role;


--
-- Name: TABLE conversations; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.conversations TO anon;
GRANT ALL ON TABLE public.conversations TO authenticated;
GRANT ALL ON TABLE public.conversations TO service_role;


--
-- Name: TABLE deep_research_settings; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.deep_research_settings TO anon;
GRANT ALL ON TABLE public.deep_research_settings TO authenticated;
GRANT ALL ON TABLE public.deep_research_settings TO service_role;


--
-- Name: TABLE document_access_events; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.document_access_events TO anon;
GRANT ALL ON TABLE public.document_access_events TO authenticated;
GRANT ALL ON TABLE public.document_access_events TO service_role;


--
-- Name: TABLE document_short_urls; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.document_short_urls TO anon;
GRANT ALL ON TABLE public.document_short_urls TO authenticated;
GRANT ALL ON TABLE public.document_short_urls TO service_role;


--
-- Name: TABLE feedback; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.feedback TO anon;
GRANT ALL ON TABLE public.feedback TO authenticated;
GRANT ALL ON TABLE public.feedback TO service_role;


--
-- Name: SEQUENCE feedback_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.feedback_id_seq TO anon;
GRANT ALL ON SEQUENCE public.feedback_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.feedback_id_seq TO service_role;


--
-- Name: TABLE icp_profiles; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.icp_profiles TO anon;
GRANT ALL ON TABLE public.icp_profiles TO authenticated;
GRANT ALL ON TABLE public.icp_profiles TO service_role;


--
-- Name: TABLE interview; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.interview TO anon;
GRANT ALL ON TABLE public.interview TO authenticated;
GRANT ALL ON TABLE public.interview TO service_role;


--
-- Name: TABLE interviewer; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.interviewer TO anon;
GRANT ALL ON TABLE public.interviewer TO authenticated;
GRANT ALL ON TABLE public.interviewer TO service_role;


--
-- Name: SEQUENCE interviewer_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.interviewer_id_seq TO anon;
GRANT ALL ON SEQUENCE public.interviewer_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.interviewer_id_seq TO service_role;


--
-- Name: TABLE organization; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.organization TO anon;
GRANT ALL ON TABLE public.organization TO authenticated;
GRANT ALL ON TABLE public.organization TO service_role;


--
-- Name: TABLE organization_files; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.organization_files TO anon;
GRANT ALL ON TABLE public.organization_files TO authenticated;
GRANT ALL ON TABLE public.organization_files TO service_role;


--
-- Name: TABLE organization_files_chunks; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.organization_files_chunks TO anon;
GRANT ALL ON TABLE public.organization_files_chunks TO authenticated;
GRANT ALL ON TABLE public.organization_files_chunks TO service_role;


--
-- Name: TABLE organization_icp_linkedin_urls; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.organization_icp_linkedin_urls TO anon;
GRANT ALL ON TABLE public.organization_icp_linkedin_urls TO authenticated;
GRANT ALL ON TABLE public.organization_icp_linkedin_urls TO service_role;


--
-- Name: TABLE organization_settings; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.organization_settings TO anon;
GRANT ALL ON TABLE public.organization_settings TO authenticated;
GRANT ALL ON TABLE public.organization_settings TO service_role;


--
-- Name: TABLE response; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.response TO anon;
GRANT ALL ON TABLE public.response TO authenticated;
GRANT ALL ON TABLE public.response TO service_role;


--
-- Name: SEQUENCE response_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.response_id_seq TO anon;
GRANT ALL ON SEQUENCE public.response_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.response_id_seq TO service_role;


--
-- Name: TABLE style_guidelines; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.style_guidelines TO anon;
GRANT ALL ON TABLE public.style_guidelines TO authenticated;
GRANT ALL ON TABLE public.style_guidelines TO service_role;


--
-- Name: SEQUENCE style_guidelines_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.style_guidelines_id_seq TO anon;
GRANT ALL ON SEQUENCE public.style_guidelines_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.style_guidelines_id_seq TO service_role;


--
-- Name: TABLE system_config; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.system_config TO anon;
GRANT ALL ON TABLE public.system_config TO authenticated;
GRANT ALL ON TABLE public.system_config TO service_role;


--
-- Name: TABLE tasks; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.tasks TO anon;
GRANT ALL ON TABLE public.tasks TO authenticated;
GRANT ALL ON TABLE public.tasks TO service_role;


--
-- Name: TABLE template_csv_export; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.template_csv_export TO anon;
GRANT ALL ON TABLE public.template_csv_export TO authenticated;
GRANT ALL ON TABLE public.template_csv_export TO service_role;


--
-- Name: TABLE token_usage; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.token_usage TO anon;
GRANT ALL ON TABLE public.token_usage TO authenticated;
GRANT ALL ON TABLE public.token_usage TO service_role;


--
-- Name: SEQUENCE token_usage_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.token_usage_id_seq TO anon;
GRANT ALL ON SEQUENCE public.token_usage_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.token_usage_id_seq TO service_role;


--
-- Name: TABLE usage; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.usage TO anon;
GRANT ALL ON TABLE public.usage TO authenticated;
GRANT ALL ON TABLE public.usage TO service_role;


--
-- Name: TABLE usage_cost_by_context; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.usage_cost_by_context TO anon;
GRANT ALL ON TABLE public.usage_cost_by_context TO authenticated;
GRANT ALL ON TABLE public.usage_cost_by_context TO service_role;


--
-- Name: TABLE usage_cost_daily; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.usage_cost_daily TO anon;
GRANT ALL ON TABLE public.usage_cost_daily TO authenticated;
GRANT ALL ON TABLE public.usage_cost_daily TO service_role;


--
-- Name: TABLE usage_cost_daily_by_campaign; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.usage_cost_daily_by_campaign TO anon;
GRANT ALL ON TABLE public.usage_cost_daily_by_campaign TO authenticated;
GRANT ALL ON TABLE public.usage_cost_daily_by_campaign TO service_role;


--
-- Name: TABLE usage_cost_daily_by_context; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.usage_cost_daily_by_context TO anon;
GRANT ALL ON TABLE public.usage_cost_daily_by_context TO authenticated;
GRANT ALL ON TABLE public.usage_cost_daily_by_context TO service_role;


--
-- Name: TABLE usage_cost_daily_with_split; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.usage_cost_daily_with_split TO anon;
GRANT ALL ON TABLE public.usage_cost_daily_with_split TO authenticated;
GRANT ALL ON TABLE public.usage_cost_daily_with_split TO service_role;


--
-- Name: TABLE usage_cost_monthly; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.usage_cost_monthly TO anon;
GRANT ALL ON TABLE public.usage_cost_monthly TO authenticated;
GRANT ALL ON TABLE public.usage_cost_monthly TO service_role;


--
-- Name: TABLE usage_cost_monthly_by_campaign; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.usage_cost_monthly_by_campaign TO anon;
GRANT ALL ON TABLE public.usage_cost_monthly_by_campaign TO authenticated;
GRANT ALL ON TABLE public.usage_cost_monthly_by_campaign TO service_role;


--
-- Name: TABLE usage_cost_monthly_by_context; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.usage_cost_monthly_by_context TO anon;
GRANT ALL ON TABLE public.usage_cost_monthly_by_context TO authenticated;
GRANT ALL ON TABLE public.usage_cost_monthly_by_context TO service_role;


--
-- Name: TABLE usage_cost_monthly_with_split; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.usage_cost_monthly_with_split TO anon;
GRANT ALL ON TABLE public.usage_cost_monthly_with_split TO authenticated;
GRANT ALL ON TABLE public.usage_cost_monthly_with_split TO service_role;


--
-- Name: TABLE usage_summary; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.usage_summary TO anon;
GRANT ALL ON TABLE public.usage_summary TO authenticated;
GRANT ALL ON TABLE public.usage_summary TO service_role;


--
-- Name: TABLE "user"; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public."user" TO anon;
GRANT ALL ON TABLE public."user" TO authenticated;
GRANT ALL ON TABLE public."user" TO service_role;


--
-- Name: TABLE user_organizations; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.user_organizations TO anon;
GRANT ALL ON TABLE public.user_organizations TO authenticated;
GRANT ALL ON TABLE public.user_organizations TO service_role;


--
-- Name: TABLE messages; Type: ACL; Schema: realtime; Owner: supabase_realtime_admin
--

GRANT ALL ON TABLE realtime.messages TO postgres;
GRANT ALL ON TABLE realtime.messages TO dashboard_user;
GRANT SELECT,INSERT,UPDATE ON TABLE realtime.messages TO anon;
GRANT SELECT,INSERT,UPDATE ON TABLE realtime.messages TO authenticated;
GRANT SELECT,INSERT,UPDATE ON TABLE realtime.messages TO service_role;


--
-- Name: TABLE messages_2026_02_13; Type: ACL; Schema: realtime; Owner: supabase_admin
--

GRANT ALL ON TABLE realtime.messages_2026_02_13 TO postgres;
GRANT ALL ON TABLE realtime.messages_2026_02_13 TO dashboard_user;


--
-- Name: TABLE messages_2026_02_14; Type: ACL; Schema: realtime; Owner: supabase_admin
--

GRANT ALL ON TABLE realtime.messages_2026_02_14 TO postgres;
GRANT ALL ON TABLE realtime.messages_2026_02_14 TO dashboard_user;


--
-- Name: TABLE messages_2026_02_15; Type: ACL; Schema: realtime; Owner: supabase_admin
--

GRANT ALL ON TABLE realtime.messages_2026_02_15 TO postgres;
GRANT ALL ON TABLE realtime.messages_2026_02_15 TO dashboard_user;


--
-- Name: TABLE messages_2026_02_16; Type: ACL; Schema: realtime; Owner: supabase_admin
--

GRANT ALL ON TABLE realtime.messages_2026_02_16 TO postgres;
GRANT ALL ON TABLE realtime.messages_2026_02_16 TO dashboard_user;


--
-- Name: TABLE messages_2026_02_17; Type: ACL; Schema: realtime; Owner: supabase_admin
--

GRANT ALL ON TABLE realtime.messages_2026_02_17 TO postgres;
GRANT ALL ON TABLE realtime.messages_2026_02_17 TO dashboard_user;


--
-- Name: TABLE messages_2026_02_18; Type: ACL; Schema: realtime; Owner: supabase_admin
--

GRANT ALL ON TABLE realtime.messages_2026_02_18 TO postgres;
GRANT ALL ON TABLE realtime.messages_2026_02_18 TO dashboard_user;


--
-- Name: TABLE messages_2026_02_19; Type: ACL; Schema: realtime; Owner: supabase_admin
--

GRANT ALL ON TABLE realtime.messages_2026_02_19 TO postgres;
GRANT ALL ON TABLE realtime.messages_2026_02_19 TO dashboard_user;


--
-- Name: TABLE schema_migrations; Type: ACL; Schema: realtime; Owner: supabase_admin
--

GRANT ALL ON TABLE realtime.schema_migrations TO postgres;
GRANT ALL ON TABLE realtime.schema_migrations TO dashboard_user;
GRANT SELECT ON TABLE realtime.schema_migrations TO anon;
GRANT SELECT ON TABLE realtime.schema_migrations TO authenticated;
GRANT SELECT ON TABLE realtime.schema_migrations TO service_role;
GRANT ALL ON TABLE realtime.schema_migrations TO supabase_realtime_admin;


--
-- Name: TABLE subscription; Type: ACL; Schema: realtime; Owner: supabase_admin
--

GRANT ALL ON TABLE realtime.subscription TO postgres;
GRANT ALL ON TABLE realtime.subscription TO dashboard_user;
GRANT SELECT ON TABLE realtime.subscription TO anon;
GRANT SELECT ON TABLE realtime.subscription TO authenticated;
GRANT SELECT ON TABLE realtime.subscription TO service_role;
GRANT ALL ON TABLE realtime.subscription TO supabase_realtime_admin;


--
-- Name: SEQUENCE subscription_id_seq; Type: ACL; Schema: realtime; Owner: supabase_admin
--

GRANT ALL ON SEQUENCE realtime.subscription_id_seq TO postgres;
GRANT ALL ON SEQUENCE realtime.subscription_id_seq TO dashboard_user;
GRANT USAGE ON SEQUENCE realtime.subscription_id_seq TO anon;
GRANT USAGE ON SEQUENCE realtime.subscription_id_seq TO authenticated;
GRANT USAGE ON SEQUENCE realtime.subscription_id_seq TO service_role;
GRANT ALL ON SEQUENCE realtime.subscription_id_seq TO supabase_realtime_admin;


--
-- Name: TABLE buckets; Type: ACL; Schema: storage; Owner: supabase_storage_admin
--

REVOKE ALL ON TABLE storage.buckets FROM supabase_storage_admin;
GRANT ALL ON TABLE storage.buckets TO supabase_storage_admin WITH GRANT OPTION;
GRANT ALL ON TABLE storage.buckets TO anon;
GRANT ALL ON TABLE storage.buckets TO authenticated;
GRANT ALL ON TABLE storage.buckets TO service_role;
GRANT ALL ON TABLE storage.buckets TO postgres WITH GRANT OPTION;


--
-- Name: TABLE buckets_analytics; Type: ACL; Schema: storage; Owner: supabase_storage_admin
--

GRANT ALL ON TABLE storage.buckets_analytics TO service_role;
GRANT ALL ON TABLE storage.buckets_analytics TO authenticated;
GRANT ALL ON TABLE storage.buckets_analytics TO anon;
GRANT ALL ON TABLE storage.buckets_analytics TO postgres;


--
-- Name: TABLE buckets_vectors; Type: ACL; Schema: storage; Owner: supabase_storage_admin
--

GRANT SELECT ON TABLE storage.buckets_vectors TO service_role;
GRANT SELECT ON TABLE storage.buckets_vectors TO authenticated;
GRANT SELECT ON TABLE storage.buckets_vectors TO anon;


--
-- Name: TABLE objects; Type: ACL; Schema: storage; Owner: supabase_storage_admin
--

REVOKE ALL ON TABLE storage.objects FROM supabase_storage_admin;
GRANT ALL ON TABLE storage.objects TO supabase_storage_admin WITH GRANT OPTION;
GRANT ALL ON TABLE storage.objects TO anon;
GRANT ALL ON TABLE storage.objects TO authenticated;
GRANT ALL ON TABLE storage.objects TO service_role;
GRANT ALL ON TABLE storage.objects TO postgres WITH GRANT OPTION;


--
-- Name: TABLE s3_multipart_uploads; Type: ACL; Schema: storage; Owner: supabase_storage_admin
--

GRANT ALL ON TABLE storage.s3_multipart_uploads TO service_role;
GRANT SELECT ON TABLE storage.s3_multipart_uploads TO authenticated;
GRANT SELECT ON TABLE storage.s3_multipart_uploads TO anon;
GRANT ALL ON TABLE storage.s3_multipart_uploads TO postgres;


--
-- Name: TABLE s3_multipart_uploads_parts; Type: ACL; Schema: storage; Owner: supabase_storage_admin
--

GRANT ALL ON TABLE storage.s3_multipart_uploads_parts TO service_role;
GRANT SELECT ON TABLE storage.s3_multipart_uploads_parts TO authenticated;
GRANT SELECT ON TABLE storage.s3_multipart_uploads_parts TO anon;
GRANT ALL ON TABLE storage.s3_multipart_uploads_parts TO postgres;


--
-- Name: TABLE vector_indexes; Type: ACL; Schema: storage; Owner: supabase_storage_admin
--

GRANT SELECT ON TABLE storage.vector_indexes TO service_role;
GRANT SELECT ON TABLE storage.vector_indexes TO authenticated;
GRANT SELECT ON TABLE storage.vector_indexes TO anon;


--
-- Name: TABLE secrets; Type: ACL; Schema: vault; Owner: supabase_admin
--

GRANT SELECT,REFERENCES,DELETE,TRUNCATE ON TABLE vault.secrets TO postgres WITH GRANT OPTION;
GRANT SELECT,DELETE ON TABLE vault.secrets TO service_role;


--
-- Name: TABLE decrypted_secrets; Type: ACL; Schema: vault; Owner: supabase_admin
--

GRANT SELECT,REFERENCES,DELETE,TRUNCATE ON TABLE vault.decrypted_secrets TO postgres WITH GRANT OPTION;
GRANT SELECT,DELETE ON TABLE vault.decrypted_secrets TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: auth; Owner: supabase_auth_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_auth_admin IN SCHEMA auth GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_auth_admin IN SCHEMA auth GRANT ALL ON SEQUENCES TO dashboard_user;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: auth; Owner: supabase_auth_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_auth_admin IN SCHEMA auth GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_auth_admin IN SCHEMA auth GRANT ALL ON FUNCTIONS TO dashboard_user;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: auth; Owner: supabase_auth_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_auth_admin IN SCHEMA auth GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_auth_admin IN SCHEMA auth GRANT ALL ON TABLES TO dashboard_user;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: extensions; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA extensions GRANT ALL ON SEQUENCES TO postgres WITH GRANT OPTION;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: extensions; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA extensions GRANT ALL ON FUNCTIONS TO postgres WITH GRANT OPTION;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: extensions; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA extensions GRANT ALL ON TABLES TO postgres WITH GRANT OPTION;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: graphql; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: graphql; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: graphql; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql GRANT ALL ON TABLES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: graphql_public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql_public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql_public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql_public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql_public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: graphql_public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql_public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql_public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql_public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql_public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: graphql_public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql_public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql_public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql_public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql_public GRANT ALL ON TABLES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: realtime; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA realtime GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA realtime GRANT ALL ON SEQUENCES TO dashboard_user;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: realtime; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA realtime GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA realtime GRANT ALL ON FUNCTIONS TO dashboard_user;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: realtime; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA realtime GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA realtime GRANT ALL ON TABLES TO dashboard_user;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: storage; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: storage; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: storage; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT ALL ON TABLES TO service_role;


--
-- Name: issue_graphql_placeholder; Type: EVENT TRIGGER; Schema: -; Owner: supabase_admin
--

CREATE EVENT TRIGGER issue_graphql_placeholder ON sql_drop
         WHEN TAG IN ('DROP EXTENSION')
   EXECUTE FUNCTION extensions.set_graphql_placeholder();


ALTER EVENT TRIGGER issue_graphql_placeholder OWNER TO supabase_admin;

--
-- Name: issue_pg_cron_access; Type: EVENT TRIGGER; Schema: -; Owner: supabase_admin
--

CREATE EVENT TRIGGER issue_pg_cron_access ON ddl_command_end
         WHEN TAG IN ('CREATE EXTENSION')
   EXECUTE FUNCTION extensions.grant_pg_cron_access();


ALTER EVENT TRIGGER issue_pg_cron_access OWNER TO supabase_admin;

--
-- Name: issue_pg_graphql_access; Type: EVENT TRIGGER; Schema: -; Owner: supabase_admin
--

CREATE EVENT TRIGGER issue_pg_graphql_access ON ddl_command_end
         WHEN TAG IN ('CREATE FUNCTION')
   EXECUTE FUNCTION extensions.grant_pg_graphql_access();


ALTER EVENT TRIGGER issue_pg_graphql_access OWNER TO supabase_admin;

--
-- Name: issue_pg_net_access; Type: EVENT TRIGGER; Schema: -; Owner: supabase_admin
--

CREATE EVENT TRIGGER issue_pg_net_access ON ddl_command_end
         WHEN TAG IN ('CREATE EXTENSION')
   EXECUTE FUNCTION extensions.grant_pg_net_access();


ALTER EVENT TRIGGER issue_pg_net_access OWNER TO supabase_admin;

--
-- Name: pgrst_ddl_watch; Type: EVENT TRIGGER; Schema: -; Owner: supabase_admin
--

CREATE EVENT TRIGGER pgrst_ddl_watch ON ddl_command_end
   EXECUTE FUNCTION extensions.pgrst_ddl_watch();


ALTER EVENT TRIGGER pgrst_ddl_watch OWNER TO supabase_admin;

--
-- Name: pgrst_drop_watch; Type: EVENT TRIGGER; Schema: -; Owner: supabase_admin
--

CREATE EVENT TRIGGER pgrst_drop_watch ON sql_drop
   EXECUTE FUNCTION extensions.pgrst_drop_watch();


ALTER EVENT TRIGGER pgrst_drop_watch OWNER TO supabase_admin;

--
-- PostgreSQL database dump complete
--

\unrestrict FD5NQNtEOa4zNib21c8d2G5VrXzTRsMrHgOkV059dzT4vwcwfCeCed8DbOsgoeT

