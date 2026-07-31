#!/usr/bin/env bash
set -Eeuo pipefail

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

anon_key="$(read_env_value "$SUPABASE_ENV" ANON_KEY)"
service_role_key="$(read_env_value "$SUPABASE_ENV" SERVICE_ROLE_KEY)"
gmail_api_key="$(read_env_value "$GMAIL_ENV" SELLTON_GMAIL_API_KEY)"

if [[ -z "$anon_key" || -z "$service_role_key" || -z "$gmail_api_key" ]]; then
  echo "one or more cutover secrets are missing" >&2
  exit 1
fi

cat <<EOF
# Vercel: selltonai production
NEXT_PUBLIC_SUPABASE_URL=https://storagedb.sellton.ai
NEXT_PUBLIC_SUPABASE_ANON_KEY=$anon_key
SUPABASE_SERVICE_ROLE_KEY=$service_role_key
MAIL_API_ENDPOINT=https://emailapi.sellton.ai
SELLTON_GMAIL_API_KEY=$gmail_api_key

# Modal main-secrets
SUPABASE_URL=https://storagedb.sellton.ai
SUPABASE_ANON_KEY=$anon_key
SUPABASE_SERVICE_ROLE_KEY=$service_role_key
SELLTON_GMAIL_API_KEY=$gmail_api_key

# Modal mail-server-secret
EMAIL_API_ENDPOINT=https://emailapi.sellton.ai
EMAIL_EVENTS_WEBHOOK_URL=https://emailapi.sellton.ai/ve/emails/inbox-events

# Hetzner Gmail API: /opt/sellton/gmail-api-prod/.env
SUPABASE_URL=https://storagedb.sellton.ai
SUPABASE_SERVICE_ROLE_KEY=$service_role_key
EXTERNAL_API_URL=https://team-9--modal-sellton-api-fastapi-app.modal.run/webhook/incoming-emails
GOOGLE_REDIRECT_URI=https://emailapi.sellton.ai/ve/auth/google/callback

# Backoffice production environment
SUPABASE_PRODUCTION_URL=https://storagedb.sellton.ai
SUPABASE_PRODUCTION_SERVICE_ROLE_KEY=$service_role_key

# Onboard, only if its production deployment writes Supabase directly
VITE_SUPABASE_URL=https://storagedb.sellton.ai
VITE_SUPABASE_ANON_KEY=$anon_key

# Crawler, only if its production deployment writes Supabase directly
SUPABASE_URL=https://storagedb.sellton.ai
SUPABASE_SERVICE_ROLE_KEY=$service_role_key
EOF

unset anon_key service_role_key gmail_api_key
