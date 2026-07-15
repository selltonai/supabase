#!/usr/bin/env bash
set -Eeuo pipefail

CUTOVER_MARKER="/opt/sellton/live-sync/CUTOVER_COMPLETE"
SUPABASE_ENV="/opt/sellton/supabase/.env"
GMAIL_ENV="/opt/sellton/gmail-api-prod/.env"

read_env_value() {
  local file_path="$1"
  local variable_name="$2"
  awk -F= -v variable_name="$variable_name" '
    $1 == variable_name {
      sub(/^[^=]*=/, "")
      print
      exit
    }
  ' "$file_path"
}

if [[ ! -s "$CUTOVER_MARKER" ]]; then
  echo "database cutover marker is missing: $CUTOVER_MARKER" >&2
  exit 1
fi
if systemctl is-active --quiet sellton-mongodb-live-mirror.service; then
  echo "MongoDB forward mirror is still active" >&2
  exit 1
fi
if systemctl is-enabled --quiet sellton-mongodb-live-mirror.service; then
  echo "MongoDB forward mirror is still enabled" >&2
  exit 1
fi
subscription_enabled="$(docker exec supabase-db psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d postgres -Atc "SELECT subenabled FROM pg_subscription WHERE subname='sellton_cloud_to_hetzner'")"
if [[ -n "$subscription_enabled" && "$subscription_enabled" != "f" ]]; then
  echo "PostgreSQL forward subscription is not disabled: ${subscription_enabled:-missing}" >&2
  exit 1
fi

/opt/sellton/live-sync/production-standby-status.sh --check

expected_service_role_key="$(read_env_value "$SUPABASE_ENV" SERVICE_ROLE_KEY)"
gmail_supabase_url="$(read_env_value "$GMAIL_ENV" SUPABASE_URL)"
gmail_service_role_key="$(read_env_value "$GMAIL_ENV" SUPABASE_SERVICE_ROLE_KEY)"
gmail_external_api_url="$(read_env_value "$GMAIL_ENV" EXTERNAL_API_URL)"
gmail_google_redirect_uri="$(read_env_value "$GMAIL_ENV" GOOGLE_REDIRECT_URI)"
gmail_pub_sub_topic="$(read_env_value "$GMAIL_ENV" PUB_SUB_TOPIC)"

if [[ "$gmail_supabase_url" != "https://storagedb.sellton.ai" ]]; then
  echo "Gmail API SUPABASE_URL is not configured for Hetzner production" >&2
  exit 1
fi
if [[ -z "$expected_service_role_key" || "$gmail_service_role_key" != "$expected_service_role_key" ]]; then
  echo "Gmail API SUPABASE_SERVICE_ROLE_KEY does not match Hetzner Supabase" >&2
  exit 1
fi
if [[ "$gmail_external_api_url" != "https://team-9--modal-sellton-api-fastapi-app.modal.run/webhook/incoming-emails" ]]; then
  echo "Gmail API EXTERNAL_API_URL is not configured for the production Modal webhook" >&2
  exit 1
fi
if [[ "$gmail_google_redirect_uri" != "https://emailapi.sellton.ai/ve/auth/google/callback" ]]; then
  echo "Gmail API GOOGLE_REDIRECT_URI is not configured for the production subdomain" >&2
  exit 1
fi
if [[ ! "$gmail_pub_sub_topic" =~ ^projects/[^/]+/topics/[^/]+$ ]]; then
  echo "Gmail API PUB_SUB_TOPIC must be copied from Render as a fully qualified production topic" >&2
  exit 1
fi
unset expected_service_role_key gmail_supabase_url gmail_service_role_key gmail_external_api_url gmail_google_redirect_uri gmail_pub_sub_topic

echo "starting the only production Gmail API scheduler"
systemctl enable --now sellton-gmail-api-prod.service
for _ in $(seq 1 60); do
  if curl -fsS https://emailapi.sellton.ai/ve/health/health >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
curl -fsS https://emailapi.sellton.ai/ve/health/health >/dev/null
echo "PRODUCTION ACTIVATED"
