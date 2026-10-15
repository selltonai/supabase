-- Reverses 394: reopens usage, usage_summary, action_label_map and the views over them to the browser's anon key,
-- exactly as before (allow-all policies, full grants). Only to undo a broken stage deploy; it restores the hole.
CREATE POLICY "Allow all operations on usage" ON public.usage FOR ALL USING (true);
CREATE POLICY "Allow all operations on usage_summary" ON public.usage_summary FOR ALL USING (true);
GRANT ALL ON TABLE public.usage, public.usage_summary, public.action_label_map TO anon, authenticated;

DO $$
DECLARE
  v_rel regclass;
BEGIN
  FOR v_rel IN
    SELECT s.oid::regclass FROM pg_class s JOIN pg_depend d ON d.objid = s.oid AND d.deptype IN ('a', 'i')
    WHERE s.relkind = 'S'
      AND d.refobjid IN ('public.usage'::regclass, 'public.usage_summary'::regclass, 'public.action_label_map'::regclass)
  LOOP
    EXECUTE format('GRANT ALL ON SEQUENCE %s TO anon, authenticated', v_rel);
  END LOOP;
  FOR v_rel IN
    SELECT DISTINCT v.oid::regclass FROM pg_depend d JOIN pg_rewrite r ON r.oid = d.objid JOIN pg_class v ON v.oid = r.ev_class
    WHERE d.refobjid IN ('public.usage'::regclass, 'public.usage_summary'::regclass, 'public.action_label_map'::regclass)
      AND v.relkind IN ('v', 'm')
      AND v.oid NOT IN ('public.usage'::regclass, 'public.usage_summary'::regclass, 'public.action_label_map'::regclass)
  LOOP
    EXECUTE format('GRANT ALL ON TABLE %s TO anon, authenticated', v_rel);
  END LOOP;
END;
$$;
