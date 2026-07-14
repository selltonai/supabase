#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

BACKOFFICE_ROOT="/opt/sellton/backoffice"
BACKOFFICE_ENV="${BACKOFFICE_ROOT}/.env"
BACKOFFICE_ENV_BACKUP="${BACKOFFICE_ROOT}/.env.before-hetzner-cutover"
SUPABASE_ENV="/opt/sellton/supabase/.env"

service_role_key="$(awk -F= '$1 == "SERVICE_ROLE_KEY" {sub(/^[^=]*=/, ""); print; exit}' "$SUPABASE_ENV")"
if [[ -z "$service_role_key" ]]; then
  echo "missing Hetzner Supabase service role key" >&2
  exit 1
fi

if [[ ! -f "$BACKOFFICE_ENV_BACKUP" ]]; then
  install -m 600 "$BACKOFFICE_ENV" "$BACKOFFICE_ENV_BACKUP"
fi

BACKOFFICE_ENV="$BACKOFFICE_ENV" SERVICE_ROLE_KEY="$service_role_key" node <<'NODE'
const fs = require('fs');
const filePath = process.env.BACKOFFICE_ENV;
let contents = fs.readFileSync(filePath, 'utf8');

function setVariable(name, value) {
  const expression = new RegExp(`^${name}=.*$`, 'gm');
  if (expression.test(contents)) {
    contents = contents.replace(expression, `${name}=${value}`);
  } else {
    contents = `${contents.replace(/\s*$/, '\n')}${name}=${value}\n`;
  }
}

setVariable('SUPABASE_PRODUCTION_URL', 'https://storagedb.sellton.ai');
setVariable('SUPABASE_PRODUCTION_SERVICE_ROLE_KEY', process.env.SERVICE_ROLE_KEY);
fs.writeFileSync(filePath, contents, {mode: 0o600});
NODE

unset service_role_key
docker compose -f "${BACKOFFICE_ROOT}/docker-compose.yml" --project-directory "$BACKOFFICE_ROOT" up -d --force-recreate backoffice

actual_url="$(docker exec backoffice-backoffice-1 printenv SUPABASE_PRODUCTION_URL)"
if [[ "$actual_url" != "https://storagedb.sellton.ai" ]]; then
  echo "backoffice production Supabase URL did not update" >&2
  exit 1
fi
echo "Backoffice production Supabase endpoint updated"
