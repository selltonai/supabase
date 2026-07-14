# Hetzner Production Live Sync

These operations keep the hosted production systems authoritative while copying changes one way to Hetzner:

- PostgreSQL: native logical replication for every application table in `public`, `auth`, and `storage`.
- Supabase Storage: two-minute object mirror.
- MongoDB: `selltonai-gmail-api/scripts/mongodb-live-mirror.js`, which performs an initial copy and then consumes a database-wide change stream.

This is temporary migration infrastructure. It is not active-active replication and it does not run reverse synchronization after cutover.

## Server Layout

The checked-in PostgreSQL and Storage files are installed below `/opt/sellton/live-sync`. MongoDB worker code is deployed with `selltonai-gmail-api` and runs as `sellton-mongodb-live-mirror.service`.

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

After updating and redeploying the Vercel and Modal production environment variables, activate the only production Gmail scheduler:

```bash
/opt/sellton/live-sync/production-activate.sh
```

Do not keep the cloud and Hetzner application writers active at the same time. The forward mirrors are one-way and must be stopped at zero lag before Hetzner becomes writable.
