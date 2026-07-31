# Hetzner Production Backup Bundles

This operation creates and downloads independent production data backups before hosted Supabase
and MongoDB Atlas are decommissioned.

## Bundle contents

The Supabase bundle contains:

- PostgreSQL custom-format database dump
- PostgreSQL global roles without role passwords
- Supabase Storage object bytes
- non-secret Docker Compose and volume configuration
- image inventory, manifest, and SHA-256 checksums

The MongoDB bundle contains:

- gzip-compressed `mongodump` archive for the production database
- non-secret replica-set Compose configuration
- collection counts, replica-set status, image inventory, manifest, and SHA-256 checksums

Both archives contain production customer data and must be stored securely. Active `.env` files,
API keys, database passwords, and the MongoDB replica-set keyfile are intentionally excluded.

## Create and download

From the Supabase repository:

```bash
operations/hetzner-production-backups/download-production-backups.sh \
  --output-dir /secure/path/sellton-production-backup
```

The command creates both bundles on Hetzner, downloads them over SSH, and verifies their checksums
locally. It keeps only the two newest bundles of each type on Hetzner.

The default mode is online and does not stop application writers:

- PostgreSQL uses an MVCC-consistent custom-format dump.
- MongoDB uses a full replica-set dump with oplog capture for point-in-time replay. MongoDB tools
  do not permit `--oplogReplay` together with namespace filtering, so restore the complete archive
  into an isolated target and use the recovered `production` database there.
- Storage uses repeated isolated `rsync` passes until a pass reports no changes, then records
  per-file checksums.

PostgreSQL and Storage cannot share one atomic snapshot because Storage bytes live on the
filesystem. Their manifests record the separate capture intervals. The recovery bundle favors
continuous production operation and a documented recovery point.

To download existing latest bundles without creating new ones:

```bash
operations/hetzner-production-backups/download-production-backups.sh --download-only
```

## Online provider decommission

Production can continue writing to Hetzner throughout this sequence:

1. Create and download fresh online bundles:

```bash
operations/hetzner-production-backups/download-production-backups.sh \
  --output-dir /secure/path/sellton-final-production-backup
```

2. Confirm each extracted `MANIFEST.txt` reports `snapshot_mode=online-point-in-time`.
3. Disable only the outgoing cloud rollback mirrors while preserving Hetzner writers and the
   weekly local PostgreSQL backup:

```bash
ssh -F /dev/null -i ~/.ssh/hetzner-api root@46.224.151.84 \
  /opt/sellton/backup-tools/disable-cloud-rollback.sh \
  --online-backups-downloaded
```

4. Verify Hetzner-only production:

```bash
ssh -F /dev/null -i ~/.ssh/hetzner-api root@46.224.151.84 \
  /opt/sellton/backup-tools/verify-hetzner-only.sh
```

5. Complete an isolated restore test and delete hosted projects.

No Vercel, Modal, Gmail API, backoffice, crawler, onboarding, Supabase, or MongoDB writer is stopped
by this online flow.

The optional `--writers-stopped` backup mode remains available for a future strict maintenance
snapshot, but is not required for provider cancellation.

## Basic archive inspection

```bash
tar -tzf supabase-production-YYYYMMDD-HHMMSS.tar.gz
tar -tzf mongodb-production-YYYYMMDD-HHMMSS.tar.gz
```

After extracting a bundle, verify its internal files:

```bash
sha256sum --check CONTENTS.sha256
```

MongoDB bundles can be tested on Hetzner in a temporary isolated container with no host port:

```bash
/opt/sellton/backup-tools/verify-mongodb-backup.sh
```

The verifier restores the full archive with oplog replay, compares collection names, checks the
recovered inventory, and removes the disposable container and data afterward.

PostgreSQL restoration remains an explicit operator procedure because it replaces database state
and requires the Supabase PostgreSQL extension set. Restore only into an isolated Supabase stack.

## Cross-project impact

- Owning projects: `selltonai-database/supabase` and `selltonai-gmail-api`
- Consumers: production operators only
- API, schema, authentication, webhook, scheduler, and environment contracts: unchanged
- Residual risk: PostgreSQL metadata and filesystem Storage bytes are separate bounded online
  snapshots rather than one atomic cross-resource snapshot
