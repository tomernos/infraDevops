#!/usr/bin/env bash
# secretfetch.sh — re-fetch all secrets from Secret Manager and restart containers.
# Run on the VM when secrets were populated AFTER first boot (empty env file).
# Usage: sudo bash ./secretfetch.sh
set -euo pipefail

PROJECT="cryptoshare-e5172"
PREFIX="swpt-mw1-sandbox"
REGION="me-west1"

fetch() {
  gcloud secrets versions access latest \
    --secret="$PREFIX-$1" \
    --project="$PROJECT" 2>/dev/null || echo ""
}

echo ">>> Fetching secrets from Secret Manager..."

{
  echo "PORT=4000"
  echo "DB_HOST=$(fetch db-host)"
  echo "DB_PORT=$(fetch db-port)"
  echo "DB_NAME=$(fetch db-name)"
  echo "DB_USER=$(fetch db-user)"
  echo "DB_PASSWORD=$(fetch db-password)"
  echo "FIREBASE_STORAGE_BUCKET=$(fetch firebase-storage-bucket)"
  echo "SERVER_KEK_MASTER_KEY=$(fetch server-kek-master-key)"
  echo "CORS_ORIGIN=$(fetch cors-origin)"
  echo "ADMIN_EMAIL=$(fetch admin-email)"
} > /etc/sweptlock/env
chmod 600 /etc/sweptlock/env

echo "--- env written ---"
cat /etc/sweptlock/env

echo "--- fetching serviceAccountKey.json ---"
gcloud secrets versions access latest \
  --secret="$PREFIX-firebase-admin-sdk-json" \
  --project="$PROJECT" \
  > /etc/sweptlock/serviceAccountKey.json
chmod 644 /etc/sweptlock/serviceAccountKey.json

echo ">>> Done. Restart containers to pick up new values:"
echo "    docker rm -f sweptlock-api && docker run -d --name sweptlock-api ..."
