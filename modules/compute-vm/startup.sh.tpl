#!/bin/bash
# Sweptlock API — VM startup script
# Runs once on first boot as root. Logs to /var/log/sweptlock-startup.log
set -euo pipefail
exec > /var/log/sweptlock-startup.log 2>&1

echo "=== Sweptlock startup: $(date) ==="

PROJECT="${project_id}"
REGION="${region}"
PREFIX="${name_prefix}"
IMAGE="${image_url}"

# ── Install Docker ────────────────────────────────────────────────────────────
echo ">>> Installing Docker..."
apt-get update -qq
apt-get install -y ca-certificates curl gnupg lsb-release

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -qq
apt-get install -y docker-ce docker-ce-cli containerd.io
systemctl enable --now docker
echo ">>> Docker installed."

# ── Auth to Artifact Registry ─────────────────────────────────────────────────
# The VM's attached service account (sa-api) authenticates automatically.
gcloud auth configure-docker $REGION-docker.pkg.dev --quiet
echo ">>> Artifact Registry auth configured."

# ── Fetch secrets from Secret Manager ────────────────────────────────────────
mkdir -p /etc/sweptlock
chmod 700 /etc/sweptlock

fetch() {
  gcloud secrets versions access latest \
    --secret="$PREFIX-$1" \
    --project="$PROJECT" 2>/dev/null || echo ""
}

echo ">>> Fetching secrets..."

# Write env file — readable by root only
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

# Write Firebase service account JSON
# 644 (not 600) — container runs as non-root and must be able to read this file
fetch firebase-admin-sdk-json > /etc/sweptlock/serviceAccountKey.json
chmod 644 /etc/sweptlock/serviceAccountKey.json

echo ">>> Secrets written."

# ── Pull image and start container ────────────────────────────────────────────
echo ">>> Pulling image: $IMAGE"
docker pull "$IMAGE"

echo ">>> Starting container..."
docker run -d \
  --name sweptlock-api \
  --restart unless-stopped \
  --env-file /etc/sweptlock/env \
  -v /etc/sweptlock/serviceAccountKey.json:/app/serviceAccountKey.json:ro \
  -p 4000:4000 \
  "$IMAGE"

echo "=== Startup complete: $(date) ==="
