# Hetzner Production Live Sync

These operations support a single-writer production migration with continuous rollback synchronization:

- Before cutover, PostgreSQL, Storage, and MongoDB copy from the hosted providers to Hetzner.
- During cutover, all writers are drained and the forward mirrors stop at zero lag.
- Before the first Hetzner write, PostgreSQL, Storage, and MongoDB standby workers start from Hetzner back to the hosted providers.

This is temporary migration infrastructure, not active-active replication. Exactly one side may receive application writes at a time. Schema changes remain frozen while rollback standby is active.

## Server Layout

The checked-in PostgreSQL and Storage files are installed below `/opt/sellton/live-sync`. MongoDB worker code is deployed with `selltonai-gmail-api`. The forward and standby workers use separate mutually exclusive systemd units.

Secrets remain in root-only files on Hetzner:

- `/root/sellton-source-pg.env`
- `/root/sellton-source.env`
- `/root/sellton-source-mongo.env`
- `/root/sellton-mongodb-live-mirror.env`

## Monitor

```bash
/opt/sellton/live-sync/production-live-sync-status.sh
```

## Cutover

First stop the current cloud Gmail API scheduler, Modal production jobs/API, Vercel writes, and any crawler/onboarding writer. Then run:

```bash
/opt/sellton/live-sync/production-cutover.sh --writers-stopped
```

The command takes a final Storage pass, verifies all three mirrors, disables PostgreSQL and Storage forward replication, synchronizes PostgreSQL sequences, stops the MongoDB mirror, and starts Hetzner Supabase. It deliberately leaves the Hetzner Gmail API stopped.

It also starts and verifies the Hetzner-to-cloud PostgreSQL, Storage, and MongoDB standby workers before Hetzner application services become writable.

After updating and redeploying the Vercel and Modal production environment variables, activate the only production Gmail scheduler:

```bash
/opt/sellton/live-sync/production-activate.sh
```

Do not keep the cloud and Hetzner application writers active at the same time. The forward mirrors are one-way and must be stopped at zero lag before Hetzner becomes writable.

## Rollback Standby

Monitor the post-cutover standby:

```bash
/opt/sellton/live-sync/production-standby-status.sh --check
```

After Hetzner is accepted as primary, retire the disabled forward PostgreSQL subscription/publication so its old cloud slot cannot retain WAL:

```bash
/opt/sellton/live-sync/production-forward-retire.sh --hetzner-primary-confirmed
```

The Hetzner-to-cloud standby remains active after retirement. To return to the hosted providers, first drain all Hetzner writers, then finalize and stop the standby with:

```bash
/opt/sellton/live-sync/production-standby-disable.sh --writers-stopped
```
