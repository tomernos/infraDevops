#!/usr/bin/env bash
# populate-secrets.sh — push all app secrets into Secret Manager.
# Reads defaults from your local .env and serviceAccountKey.json.
# Run from the sweptlock-infra/ root after database apply.
# Usage: ./scripts/populate-secrets.sh
set -euo pipefail

PROJECT_ID="${1:-cryptoshare-e5172}"
PREFIX="swpt-mw1-sandbox"

INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── Machine-specific paths — update when switching machines ───────────────────
APP_DIR="${APP_DIR:-/mnt/c/Users/tomer/Desktop/PersonalGitProjects/Sweptlock/backend}"   # Windows (WSL)
# APP_DIR="${APP_DIR:-$HOME/Desktop/PersonalGitProjects/Sweptlock/backend}"               # Mac
PLATFORM_API_DIR="${PLATFORM_API_DIR:-/mnt/c/Users/tomer/Desktop/PersonalGitProjects/sweptlock-platform/api}"

ENV_FILE="$APP_DIR/.env"
SA_KEY_FILE="$APP_DIR/serviceAccountKey.json"
PLATFORM_ENV_FILE="$PLATFORM_API_DIR/.env"

echo "=== Populating Secret Manager: $PROJECT_ID ==="
echo ""

# ── Validate required files exist ─────────────────────────────────────────────
[[ -f "$ENV_FILE" ]]    || { echo "ERROR: $ENV_FILE not found"; exit 1; }
[[ -f "$SA_KEY_FILE" ]] || { echo "ERROR: $SA_KEY_FILE not found"; exit 1; }

# ── Read values from .env ─────────────────────────────────────────────────────
read_env() {
  grep -E "^${1}=" "$1" | cut -d'=' -f2- | tr -d '"' || echo ""
}

read_from_file() {
  local file="$1"
  local key="$2"
  grep -E "^${key}=" "$file" 2>/dev/null | cut -d'=' -f2- | tr -d '"' || echo ""
}

FIREBASE_BUCKET="$(read_from_file "$ENV_FILE" FIREBASE_STORAGE_BUCKET)"
KEK="$(read_from_file "$ENV_FILE" SERVER_KEK_MASTER_KEY)"
ADMIN_EMAIL="$(read_from_file "$ENV_FILE" ADMIN_EMAIL)"
CORS_ORIGIN="${CORS_ORIGIN:-*}"

# ── Read DB outputs from Terraform ────────────────────────────────────────────
echo ">>> Reading Cloud SQL outputs from Terraform..."
DB_HOST=$(cd "$INFRA_DIR/regions/me-west1/sandbox/database" \
  && terragrunt output -raw private_ip 2>/dev/null) || DB_HOST=""
DB_PASSWORD=$(cd "$INFRA_DIR/regions/me-west1/sandbox/database" \
  && terragrunt output -raw db_password 2>/dev/null) || DB_PASSWORD=""

[[ -n "$DB_HOST" ]]     || { echo "ERROR: Could not read private_ip from database output. Run 'terragrunt apply' in database stack first."; exit 1; }
[[ -n "$DB_PASSWORD" ]] || { echo "ERROR: Could not read db_password from database output."; exit 1; }

DB_PORT="5432"
DB_NAME="sweptlock_db"
DB_USER="sweptlock"

# ── Push helper ───────────────────────────────────────────────────────────────
push() {
  local secret_id="$PREFIX-$1"
  local value="$2"
  if [[ -z "$value" ]]; then
    echo "  SKIP  $secret_id  (empty value)"
    return
  fi
  echo -n "$value" | gcloud secrets versions add "$secret_id" \
    --project="$PROJECT_ID" \
    --data-file=- \
    --quiet 2>/dev/null && echo "  OK    $secret_id" || echo "  FAIL  $secret_id"
}

# ── Main app secrets ──────────────────────────────────────────────────────────
echo ">>> Pushing main app secrets..."
push "db-host"                  "$DB_HOST"
push "db-port"                  "$DB_PORT"
push "db-name"                  "$DB_NAME"
push "db-user"                  "$DB_USER"
push "db-password"              "$DB_PASSWORD"
push "firebase-storage-bucket"  "$FIREBASE_BUCKET"
push "server-kek-master-key"    "$KEK"
push "cors-origin"              "$CORS_ORIGIN"
push "admin-email"              "$ADMIN_EMAIL"

# Firebase Admin SDK JSON — push from file directly
echo -n "$(cat "$SA_KEY_FILE")" | gcloud secrets versions add "$PREFIX-firebase-admin-sdk-json" \
  --project="$PROJECT_ID" \
  --data-file=- \
  --quiet 2>/dev/null && echo "  OK    $PREFIX-firebase-admin-sdk-json" \
  || echo "  FAIL  $PREFIX-firebase-admin-sdk-json"

# ── Platform API secrets ──────────────────────────────────────────────────────
echo ""
echo ">>> Pushing platform API secrets..."

# Platform DB: defaults to same DB host/password, separate DB user (sweptlock_platform_user).
# Override with PLATFORM_DB_USER / PLATFORM_DB_PASSWORD env vars before running.
PLATFORM_DB_USER="${PLATFORM_DB_USER:-sweptlock}"
PLATFORM_DB_PASSWORD="${PLATFORM_DB_PASSWORD:-$DB_PASSWORD}"

# PRIVATE_BIND_IP: the Tailscale / VPC private IP the platform API and NGINX bind to.
# Set this to your Tailscale IP (100.x.x.x) or GCP VPC internal IP before running.
PRIVATE_BIND_IP="${PRIVATE_BIND_IP:-}"
[[ -n "$PRIVATE_BIND_IP" ]] || echo "  WARN  PRIVATE_BIND_IP not set — platform-private-ip will be skipped"

# PLATFORM_CORS_ORIGINS: URL(s) of the platform panel (comma-separated for multiple).
# In production this is the panel's private URL, e.g. http://100.x.x.x:8080
PLATFORM_CORS_ORIGINS="${PLATFORM_CORS_ORIGINS:-$(read_from_file "$PLATFORM_ENV_FILE" CORS_ORIGINS 2>/dev/null)}"

FIREBASE_PROJECT_ID="$(read_from_file "$ENV_FILE" FIREBASE_PROJECT_ID)"
[[ -n "$FIREBASE_PROJECT_ID" ]] || FIREBASE_PROJECT_ID="$(read_from_file "$PLATFORM_ENV_FILE" FIREBASE_PROJECT_ID 2>/dev/null)"

push "platform-db-user"       "$PLATFORM_DB_USER"
push "platform-db-password"   "$PLATFORM_DB_PASSWORD"
push "platform-private-ip"    "$PRIVATE_BIND_IP"
push "platform-cors-origins"  "$PLATFORM_CORS_ORIGINS"
push "firebase-project-id"    "$FIREBASE_PROJECT_ID"

echo ""
echo "=== Done. Verify in console: https://console.cloud.google.com/security/secret-manager?project=$PROJECT_ID ==="
