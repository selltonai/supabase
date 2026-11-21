-- Rollback of 449_stage-cron-app-url: the stage cron calls the address it had before 449 (kept by 449 in the row
-- public_app_url_before_449). Only a row that 449 set is changed back; on a database 449 did not change, nothing.
UPDATE sellton_internal.cron_config c
   SET value = b.value, updated_at = NOW()
  FROM sellton_internal.cron_config b
 WHERE c.key = 'public_app_url'
   AND c.value = 'https://stage-ver.sellton.ai'
   AND b.key = 'public_app_url_before_449';
DELETE FROM sellton_internal.cron_config WHERE key = 'public_app_url_before_449';
