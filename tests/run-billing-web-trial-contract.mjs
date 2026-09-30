// Runs only an in-memory PostgreSQL database. Install PGlite outside this repo,
// then set PGLITE_MODULE_PATH to its dist/index.js; see docs/cross-project/README.md.
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { randomUUID } from 'node:crypto'
const { PGlite } = await import(process.env.PGLITE_MODULE_PATH || '@electric-sql/pglite')
const db = new PGlite()
const root = new URL('../', import.meta.url)
const read = (path) => readFileSync(new URL(path, root), 'utf8')
let checks = 0
const check = (name, condition) => { assert.ok(condition, name); checks++; console.log(`PASS ${name}`) }
const one = async (sql, params) => (await db.query(sql, params)).rows[0]
const apply = async (path) => db.transaction(async (tx) => tx.exec(read(path)))
const rpc = async (action, org, operation = randomUUID(), now = '2026-10-12T09:00:00Z', actor = 'anna@sellton.ai') =>
  (await one(`SELECT public.${action}_billing_web_trial($1,$2,$3,$4) AS result`, [org, actor, operation, now])).result
const count = async (table, org) => (await one(`SELECT count(*)::integer AS n FROM public.${table} WHERE organization_id=$1`, [org])).n
const refuses = async (name, execute, pattern) => {
  await assert.rejects(execute, pattern)
  checks++; console.log(`PASS ${name}`)
}

try {
  await db.exec(read('tests/fixtures/billing-web-trial-bootstrap.sql'))
  for (const path of ['migrations/release_1.1.0/243_billing.sql', 'migrations/release_1.2.0/306_create_org_seats.sql', 'migrations/release_1.2.0/307_create_activation_fees.sql', 'migrations/next-release/382_billing-model.sql']) await apply(path)
  await db.exec(`INSERT INTO public.organization(id) VALUES ('fresh'),('existing'),('rollback'),('rollback_existing'),('custom_config'),('end_failure'),('zero'),('legacy'),('no_audit'),('bad_setting'),('overlap');
    INSERT INTO public.billing_customers(organization_id,status,auto_charge_enabled) VALUES ('existing','suspended',false);
    INSERT INTO public.billing_customers(organization_id,status,auto_charge_enabled) VALUES ('rollback_existing','suspended',false);
    INSERT INTO public.billing_customers(organization_id,trial_started_at,trial_ends_at) VALUES ('legacy','2026-10-12T09:00:00Z','2026-10-19T09:00:00Z');
    INSERT INTO public.billing_credits(organization_id,kind,amount_usd,remaining_usd,source,created_by) VALUES
      ('legacy','trial',40,40,'backoffice_trial','staff'), ('legacy','trial',10,10,'mobile_trial','mobile'), ('legacy','manual',5,5,'goodwill','staff');`)
  const migration = 'migrations/next-release/384_billing-web-trial-transactions.sql'
  const sql = read(migration)
  check('migration is transaction compatible', !sql.split('\n').some((line) => /^\s*(BEGIN|COMMIT|ROLLBACK)\s*;/i.test(line)))
  await apply(migration)
  await db.exec(`UPDATE public.billing_settings SET value=3 WHERE key='trial_mobile_days'; UPDATE public.billing_settings SET value=5 WHERE key='trial_mobile_credit_usd';`)
  check('legacy web credit is classified without touching phone/manual credits', (await one(`SELECT count(*)=1 AS ok FROM public.billing_credits WHERE trial_product='web'`)).ok)
  check('legacy manual credits remain valid with a null product', (await one(`SELECT trial_product IS NULL AS ok FROM public.billing_credits WHERE kind='manual'`)).ok)
  const legacyEnded = await rpc('end','legacy',randomUUID(),'2026-10-12T09:00:01Z')
  check('an existing pre-RPC web trial can end while preserving legacy phone credit', Number(legacyEnded.unused_trial_credit_usd) === 40 && (await one(`SELECT remaining_usd=10 AND trial_product IS NULL AS ok FROM public.billing_credits WHERE source='mobile_trial' AND organization_id='legacy'`)).ok)

  const startOperation = randomUUID()
  const started = await rpc('start', 'fresh', startOperation)
  check('start creates customer, web credit and one audit', await count('billing_customers','fresh') === 1 && await count('billing_credits','fresh') === 1 && await count('backoffice_audit_events','fresh') === 1)
  const credit = await one(`SELECT * FROM public.billing_credits WHERE id=$1`, [started.credit_id])
  check('web trial uses web settings and its credit has the matching expiry', Number(credit.amount_usd) === 40 && credit.trial_product === 'web' && Date.parse(credit.expires_at) === Date.parse(started.trial_ends_at))
  check('first customer creation is recorded', started.created_customer_row === true)
  check('web trial length ignores the different phone trial length', Date.parse(started.trial_ends_at) - Date.parse(started.trial_started_at) === 7*24*60*60*1000)
  check('replaying a committed start returns its original receipt', JSON.stringify(await rpc('start','fresh',startOperation)) === JSON.stringify(started))
  check('replay does not duplicate credits or audits', await count('billing_credits','fresh') === 1 && await count('backoffice_audit_events','fresh') === 1)
  await refuses('a second independent start is refused', () => rpc('start','fresh'), /already had a web trial/)
  await refuses('receipt cannot be replayed for another org', () => rpc('start','existing',startOperation), /different request/)
  await refuses('receipt cannot be replayed by another actor', () => rpc('start','fresh',startOperation,undefined,'other@sellton.ai'), /different request/)
  await refuses('receipt cannot be replayed as another action', () => rpc('end','fresh',startOperation), /different request/)

  const existing = await rpc('start','existing')
  const customer = await one(`SELECT * FROM public.billing_customers WHERE organization_id='existing'`)
  check('existing billing flags and suspension are preserved', !existing.created_customer_row && customer.status === 'suspended' && customer.auto_charge_enabled === false)
  await db.exec(`UPDATE public.billing_settings SET value=5 WHERE key='trial_web_days'; UPDATE public.billing_settings SET value=12.50 WHERE key='trial_web_credit_usd';`)
  const configured = await rpc('start','custom_config')
  check('web trial length and amount follow edited settings', Number(configured.trial_credit_usd) === 12.5 && Date.parse(configured.trial_ends_at) - Date.parse(configured.trial_started_at) === 5*24*60*60*1000)
  await db.exec(`UPDATE public.billing_settings SET value=7 WHERE key='trial_web_days'; UPDATE public.billing_settings SET value=40 WHERE key='trial_web_credit_usd';`)

  await db.exec(`CREATE FUNCTION public.fail_trial_credit() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
    IF NEW.organization_id LIKE 'rollback%' THEN RAISE EXCEPTION 'injected credit failure'; END IF; RETURN NEW; END $$;
    CREATE TRIGGER fail_trial_credit BEFORE INSERT ON public.billing_credits FOR EACH ROW EXECUTE FUNCTION public.fail_trial_credit();`)
  await refuses('credit insert failure refuses start', () => rpc('start','rollback'), /injected credit failure/)
  check('failed start rolls back customer, credit, receipt and audit', await count('billing_customers','rollback') === 0 && await count('billing_credits','rollback') === 0 && await count('billing_web_trial_operations','rollback') === 0 && await count('backoffice_audit_events','rollback') === 0)
  await refuses('credit failure also rolls back an existing customer start', () => rpc('start','rollback_existing'), /injected credit failure/)
  check('existing customer retains its original state after rollback', (await one(`SELECT trial_started_at IS NULL AND trial_ends_at IS NULL AND status='suspended' AND NOT auto_charge_enabled AS ok FROM public.billing_customers WHERE organization_id='rollback_existing'`)).ok && await count('billing_web_trial_operations','rollback_existing') === 0)
  await db.exec('DROP TRIGGER fail_trial_credit ON public.billing_credits')
  await rpc('start','rollback')
  check('a rolled-back start can be retried', await count('billing_credits','rollback') === 1)

  await db.exec(`INSERT INTO public.billing_credits(organization_id,kind,trial_product,amount_usd,remaining_usd,source,created_by) VALUES
    ('fresh','trial','mobile',10,10,'mobile_trial','mobile'), ('fresh','manual',NULL,5,5,'goodwill','staff'), ('fresh','trial',NULL,3,3,'unknown','other');`)
  const endOperation = randomUUID()
  const ended = await rpc('end','fresh',endOperation,'2026-10-12T09:00:01Z')
  check('end closes precisely the web trial credit', ended.closed_credit_ids.length === 1 && ended.closed_credit_ids[0] === started.credit_id && Number(ended.unused_trial_credit_usd) === 40)
  check('phone, manual and unclassified credits remain available', (await one(`SELECT count(*)=3 AS ok FROM public.billing_credits WHERE organization_id='fresh' AND remaining_usd>0`)).ok)
  check('web trial dates and credit end together', (await one(`SELECT c.trial_ends_at=b.expires_at AND b.remaining_usd=0 AS ok FROM public.billing_customers c JOIN public.billing_credits b ON b.id=$1 WHERE c.organization_id='fresh'`,[started.credit_id])).ok)
  check('end replay returns its original result', JSON.stringify(await rpc('end','fresh',endOperation,'2026-10-12T09:00:02Z')) === JSON.stringify(ended))
  check('end replay does not duplicate audits', await count('backoffice_audit_events','fresh') === 2)
  await refuses('second end is refused even with an earlier request timestamp', () => rpc('end','fresh',randomUUID(),'2026-10-12T09:00:00Z'), /No web trial is running/)
  check('start receipt survives a later end without changing state', JSON.stringify(await rpc('start','fresh',startOperation)) === JSON.stringify(started) && (await one(`SELECT remaining_usd=0 AS ok FROM public.billing_credits WHERE id=$1`,[started.credit_id])).ok)

  const beforeFailure = await rpc('start','end_failure')
  await db.exec(`CREATE FUNCTION public.fail_trial_end() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
    IF NEW.organization_id='end_failure' AND NEW.trial_ends_at<OLD.trial_ends_at THEN RAISE EXCEPTION 'injected end failure'; END IF; RETURN NEW; END $$;
    CREATE TRIGGER fail_trial_end BEFORE UPDATE ON public.billing_customers FOR EACH ROW EXECUTE FUNCTION public.fail_trial_end();`)
  await refuses('customer end failure refuses the atomic action', () => rpc('end','end_failure',randomUUID(),'2026-10-12T09:00:01Z'), /injected end failure/)
  check('failed end leaves the credit available and the trial running', (await one(`SELECT b.remaining_usd=40 AND c.trial_ends_at=b.expires_at AS ok FROM public.billing_customers c JOIN public.billing_credits b ON b.id=$1 WHERE c.organization_id='end_failure'`,[beforeFailure.credit_id])).ok && await count('billing_web_trial_operations','end_failure') === 1 && await count('backoffice_audit_events','end_failure') === 1)
  await db.exec('DROP TRIGGER fail_trial_end ON public.billing_customers')
  await rpc('end','end_failure',randomUUID(),'2026-10-12T09:00:01Z')

  await db.exec(`UPDATE public.billing_settings SET value=0 WHERE key='trial_web_credit_usd'`)
  const zeroOperation = randomUUID()
  const zero = await rpc('start','zero',zeroOperation)
  check('zero-credit trial starts with a replayable receipt and no credit row', zero.credit_id === null && await count('billing_credits','zero') === 0 && JSON.stringify(await rpc('start','zero',zeroOperation)) === JSON.stringify(zero))
  await rpc('end','zero',randomUUID(),'2026-10-12T09:00:01Z')
  for (const days of [0,366,2.5]) {
    await db.query(`UPDATE public.billing_settings SET value=$1 WHERE key='trial_web_days'`,[days])
    await refuses(`invalid ${days}-day trial changes nothing`, () => rpc('start','bad_setting'), /trial_web_days/)
  }
  check('invalid settings never create a customer or receipt', await count('billing_customers','bad_setting') === 0 && await count('billing_web_trial_operations','bad_setting') === 0)
  await db.exec(`UPDATE public.billing_settings SET value=7 WHERE key='trial_web_days'; UPDATE public.billing_settings SET value=40 WHERE key='trial_web_credit_usd';`)

  await db.exec(`CREATE FUNCTION public.fail_trial_audit() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'injected audit failure'; END $$;
    CREATE TRIGGER fail_trial_audit BEFORE INSERT ON public.backoffice_audit_events FOR EACH ROW EXECUTE FUNCTION public.fail_trial_audit();`)
  const noAudit = await rpc('start','no_audit')
  await rpc('end','no_audit',randomUUID(),'2026-10-12T09:00:01Z')
  check('audit failure never rolls back the trial action', noAudit.credit_id && await count('billing_web_trial_operations','no_audit') === 2 && await count('backoffice_audit_events','no_audit') === 0)
  await db.exec('DROP TRIGGER fail_trial_audit ON public.backoffice_audit_events')

  // Concurrent caller promises use one atomic SQL statement per action. PGlite
  // queues its single connection; separate-session row-lock contention is not exercised.
  const overlappingStart = rpc('start','overlap')
  const overlappingEnd = rpc('end','overlap',randomUUID(),'2026-10-12T09:00:01Z')
  await Promise.all([overlappingStart,overlappingEnd])
  check('overlapping calls cannot leave available web credit after end', (await one(`SELECT count(*)=0 AS ok FROM public.billing_credits WHERE organization_id='overlap' AND trial_product='web' AND remaining_usd>0`)).ok)

  for (const role of ['anon','authenticated']) {
    check(`${role} cannot execute either trial RPC`, (await one(`SELECT NOT has_function_privilege($1,'public.start_billing_web_trial(text,text,uuid,timestamptz)','EXECUTE') AND NOT has_function_privilege($1,'public.end_billing_web_trial(text,text,uuid,timestamptz)','EXECUTE') AS ok`,[role])).ok)
    check(`${role} cannot read operation receipts`, (await one(`SELECT NOT has_table_privilege($1,'public.billing_web_trial_operations','SELECT') AS ok`,[role])).ok)
  }
  check('service_role can execute RPCs but cannot directly change receipts', (await one(`SELECT has_function_privilege('service_role','public.start_billing_web_trial(text,text,uuid,timestamptz)','EXECUTE') AND has_function_privilege('service_role','public.end_billing_web_trial(text,text,uuid,timestamptz)','EXECUTE') AND NOT has_table_privilege('service_role','public.billing_web_trial_operations','INSERT,UPDATE,DELETE') AS ok`)).ok)
  await db.exec('SET ROLE service_role')
  const replayedAsService = await rpc('start','fresh',startOperation)
  await db.exec('RESET ROLE')
  check('service-role invocation can replay the definer transaction', JSON.stringify(replayedAsService) === JSON.stringify(started))
  await refuses('an unknown organization is refused', () => rpc('start','missing'), /Organization not found/)

  const snapshotSql = `SELECT jsonb_build_object('receipts',(SELECT jsonb_agg(to_jsonb(r) ORDER BY operation_id) FROM public.billing_web_trial_operations r),'credits',(SELECT jsonb_agg(to_jsonb(c) ORDER BY id) FROM public.billing_credits c),'customers',(SELECT jsonb_agg(to_jsonb(b) ORDER BY id) FROM public.billing_customers b)) AS data`
  const snapshot = JSON.stringify((await one(snapshotSql)).data)
  await apply(migration)
  check('reapplying migration preserves receipts, dates and credits', JSON.stringify((await one(snapshotSql)).data) === snapshot)
  console.log(`\n${checks}/${checks} checks passed`)
} finally {
  await db.close()
}
