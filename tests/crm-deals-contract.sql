\set ON_ERROR_STOP on

-- Run with:
--   psql -X -v ON_ERROR_STOP=1 -f tests/crm-deals-contract.sql
-- The entire suite, including migration application and fixtures, rolls back.
BEGIN;

\ir ../migrations/release-next/344_crm-deals-foundation.sql
\ir ../migrations/release-next/345_crm-deals-contact-projection.sql

INSERT INTO public.organization (id, name)
VALUES ('org_crm_pipeline_validation', 'CRM Pipeline Validation');

INSERT INTO public.organization_settings (organization_id, default_deal_amount, default_deal_currency)
VALUES ('org_crm_pipeline_validation', 25000, 'EUR');

INSERT INTO public.companies (id, organization_id, name)
VALUES ('10000000-0000-0000-0000-000000000001', 'org_crm_pipeline_validation', 'Validation Company');

-- Contacts are commonly inserted before company_contacts. The relationship
-- trigger must project the deal once the company becomes known.
INSERT INTO public.contacts (id, organization_id, name, pipeline_stage, stage_updated_at)
VALUES (
  '20000000-0000-0000-0000-000000000001',
  'org_crm_pipeline_validation',
  'Validation Contact One',
  'LEAD',
  NOW() - INTERVAL '1 day'
);

INSERT INTO public.company_contacts (organization_id, company_id, contact_id)
VALUES (
  'org_crm_pipeline_validation',
  '10000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000001'
);

DO $$
DECLARE
  v_deal public.deals;
BEGIN
  SELECT * INTO STRICT v_deal
  FROM public.deals
  WHERE organization_id = 'org_crm_pipeline_validation'
    AND company_id = '10000000-0000-0000-0000-000000000001'
    AND closed_at IS NULL;

  IF v_deal.stage <> 'LEAD' OR v_deal.amount <> 25000 OR v_deal.currency <> 'EUR' THEN
    RAISE EXCEPTION 'Relationship projection did not use expected stage/defaults: %', ROW_TO_JSON(v_deal);
  END IF;
END
$$;

UPDATE public.contacts
SET pipeline_stage = 'APPOINTMENT_SCHEDULED', stage_updated_at = NOW()
WHERE id = '20000000-0000-0000-0000-000000000001';

DO $$
DECLARE
  v_deal_id UUID;
  v_stage TEXT;
BEGIN
  SELECT id, stage INTO STRICT v_deal_id, v_stage
  FROM public.deals
  WHERE organization_id = 'org_crm_pipeline_validation'
    AND company_id = '10000000-0000-0000-0000-000000000001'
    AND closed_at IS NULL;

  IF v_stage <> 'MEETING_BOOKED' THEN
    RAISE EXCEPTION 'Automatic forward projection failed: %', v_stage;
  END IF;

  PERFORM public.update_crm_deal(
    v_deal_id,
    'org_crm_pipeline_validation',
    NULL,
    '{"stage":"LEAD"}'::JSONB
  );
END
$$;

-- An unrelated contact update cannot overwrite a manual deal regression.
UPDATE public.contacts
SET updated_at = NOW()
WHERE id = '20000000-0000-0000-0000-000000000001';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.deals
    WHERE organization_id = 'org_crm_pipeline_validation'
      AND stage = 'LEAD'
      AND closed_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Manual deal stage was overwritten without a new contact stage event';
  END IF;
END
$$;

UPDATE public.contacts
SET pipeline_stage = 'CONTRACT_NEGOTIATIONS', stage_updated_at = NOW()
WHERE id = '20000000-0000-0000-0000-000000000001';

-- CLOSED_WON is ignored because deal wins are manual-only.
UPDATE public.contacts
SET pipeline_stage = 'CLOSED_WON', stage_updated_at = NOW()
WHERE id = '20000000-0000-0000-0000-000000000001';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.deals
    WHERE organization_id = 'org_crm_pipeline_validation'
      AND stage = 'NEGOTIATION'
      AND closed_at IS NULL
  ) THEN
    RAISE EXCEPTION 'CLOSED_WON contact event changed the authoritative deal';
  END IF;
END
$$;

-- A lost contact cannot close the company deal while another active contact exists.
INSERT INTO public.contacts (id, organization_id, name, pipeline_stage, stage_updated_at)
VALUES (
  '20000000-0000-0000-0000-000000000002',
  'org_crm_pipeline_validation',
  'Validation Contact Two',
  'LEAD',
  NOW()
);

INSERT INTO public.company_contacts (organization_id, company_id, contact_id)
VALUES (
  'org_crm_pipeline_validation',
  '10000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000002'
);

UPDATE public.contacts
SET pipeline_stage = 'CLOSED_LOST', stage_updated_at = NOW()
WHERE id = '20000000-0000-0000-0000-000000000001';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.deals
    WHERE organization_id = 'org_crm_pipeline_validation'
      AND stage = 'NEGOTIATION'
      AND closed_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Deal closed while another company contact was active';
  END IF;
END
$$;

UPDATE public.contacts
SET pipeline_stage = 'CLOSED_LOST', stage_updated_at = NOW()
WHERE id = '20000000-0000-0000-0000-000000000002';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.deals
    WHERE organization_id = 'org_crm_pipeline_validation'
      AND stage = 'LOST'
      AND closed_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Deal did not close after the last active company contact was lost';
  END IF;
END
$$;

-- Projection errors are logged and cannot roll back the source write.
INSERT INTO public.companies (id, organization_id, name)
VALUES ('10000000-0000-0000-0000-000000000002', 'org_crm_pipeline_validation', '');

INSERT INTO public.contacts (id, organization_id, name, pipeline_stage)
VALUES ('20000000-0000-0000-0000-000000000003', 'org_crm_pipeline_validation', 'Failure Contact', 'LEAD');

INSERT INTO public.company_contacts (organization_id, company_id, contact_id)
VALUES (
  'org_crm_pipeline_validation',
  '10000000-0000-0000-0000-000000000002',
  '20000000-0000-0000-0000-000000000003'
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.crm_deal_projection_failures
    WHERE organization_id = 'org_crm_pipeline_validation'
      AND contact_id = '20000000-0000-0000-0000-000000000003'
  ) THEN
    RAISE EXCEPTION 'Projection failure did not reach the failure ledger';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.company_contacts
    WHERE contact_id = '20000000-0000-0000-0000-000000000003'
  ) THEN
    RAISE EXCEPTION 'Projection failure rolled back the source relationship write';
  END IF;

  IF EXISTS (
    SELECT organization_id, company_id
    FROM public.deals
    WHERE closed_at IS NULL
    GROUP BY organization_id, company_id
    HAVING COUNT(*) > 1
  ) THEN
    RAISE EXCEPTION 'More than one open deal exists for a company';
  END IF;

  IF has_table_privilege('authenticated', 'public.deals', 'SELECT') THEN
    RAISE EXCEPTION 'Authenticated gained direct deal-table access';
  END IF;

  IF has_function_privilege('authenticated', 'public.update_crm_deal(uuid,text,text,jsonb)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Authenticated gained direct deal mutation access';
  END IF;
END
$$;

SELECT 'crm-deals-contract: ok' AS result;

ROLLBACK;
