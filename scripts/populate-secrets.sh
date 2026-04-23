#!/usr/bin/env bash
# populate-secrets.sh — push all app secrets into Secret Manager.
# Reads defaults from your local .env and serviceAccountKey.json.
# Run from the sweptlock-infra/ root after database apply.
# Usage: ./scripts/populate-secrets.sh
set -euo pipefail

PROJECT_ID="${1:-cryptoshare-e5172}"
PREFIX="swpt-mw1-sandbox"

# Paths to your app files
INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="/mnt/c/Users/tomer/Desktop/PersonalGitProjects/Aladin/aladin-backend"
ENV_FILE="$APP_DIR/.env"
SA_KEY_FILE="$APP_DIR/serviceAccountKey.json"

echo "=== Populating Secret Manager: $PROJECT_ID ==="
echo ""

# ── Validate required files exist ─────────────────────────────────────────────
[[ -f "$ENV_FILE" ]]    || { echo "ERROR: $ENV_FILE not found"; exit 1; }
[[ -f "$SA_KEY_FILE" ]] || { echo "ERROR: $SA_KEY_FILE not found"; exit 1; }

# ── Read values from .env ─────────────────────────────────────────────────────
read_env() {
  grep -E "^${1}=" "$ENV_FILE" | cut -d'=' -f2- | tr -d '"' || echo ""
}

FIREBASE_BUCKET="$(read_env FIREBASE_STORAGE_BUCKET)"
KEK="$(read_env SERVER_KEK_MASTER_KEY)"
ADMIN_EMAIL="$(read_env ADMIN_EMAIL)"
CORS_ORIGIN="${CORS_ORIGIN:-*}"

# ── Read DB outputs from Terraform ────────────────────────────────────────────
echo ">>> Reading Cloud SQL outputs from Terraform..."
DB_HOST=$(cd "$INFRA_DIR/regions/me-west1/sandbox/database" \
  && terragrunt output -raw private_ip 2>/dev/null) || DB_HOST=""
DB_PASSWORD=$(cd "$INFRA_DIR/regions/me-west1/sandbox/database" \
  && terragrunt output -raw db_password 2>/dev/null) || DB_PASSWORD=""

[[ -n "$DB_HOST" ]]     || { echo "ERROR: Could not read private_ip from database output. Run 'terragrunt apply' in database stack first."; exit 1; }
[[ -n "$DB_PASSWORD" ]] || { echo "ERROR: Could not read db_password from database output."; exit 1; }

# Known static DB values
DB_PORT="5432"
DB_NAME="aladin_db"
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

# ── Push all secrets ──────────────────────────────────────────────────────────
echo ">>> Pushing secrets..."
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

echo ""
echo "=== Done. Verify in console: https://console.cloud.google.com/security/secret-manager?project=$PROJECT_ID ==="
