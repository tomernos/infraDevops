#!/bin/bash
# Sweptlock VM — first-boot script
# Installs Docker, writes a systemd service that fetches secrets + runs containers on every boot.
set -euo pipefail
exec > /var/log/sweptlock-startup.log 2>&1

echo "=== Sweptlock first-boot: $(date) ==="

# ── Install Docker ────────────────────────────────────────────────────────────
echo ">>> Installing Docker..."
apt-get update -qq
apt-get install -y ca-certificates curl gnupg lsb-release

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg \
  | gpg --batch --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -qq
apt-get install -y docker-ce docker-ce-cli containerd.io
systemctl enable --now docker
echo ">>> Docker installed."

mkdir -p /etc/sweptlock
chmod 700 /etc/sweptlock

# ── Write sweptlock-start.sh ──────────────────────────────────────────────────
# Runs on every boot via systemd. Fetches fresh secrets, recreates containers.
# Uses __PLACEHOLDERS__ replaced by sed below to avoid Terraform template conflicts.
cat > /usr/local/bin/sweptlock-start.sh << 'STARTSCRIPT'
#!/bin/bash
set -euo pipefail
exec >> /var/log/sweptlock-startup.log 2>&1

PROJECT="__PROJECT__"
PREFIX="__PREFIX__"
REGION="__REGION__"
IMAGE="__IMAGE__"
WEB_IMAGE="__WEB_IMAGE__"
PLATFORM_API_IMAGE="__PLATFORM_API_IMAGE__"
PLATFORM_PANEL_IMAGE="__PLATFORM_PANEL_IMAGE__"

fetch() {
  gcloud secrets versions access latest \
    --secret="$${PREFIX}-$1" \
    --project="$${PROJECT}" 2>/dev/null || echo ""
}

echo "=== sweptlock-start: $(date) ==="
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

# Fetch platform-specific secrets
PRIVATE_BIND_IP="$(fetch platform-private-ip)"
PLATFORM_CORS_ORIGINS="$(fetch platform-cors-origins)"

{
  echo "PORT=5001"
  echo "BIND_HOST=127.0.0.1"
  echo "DATABASE_SSL=off"
  echo "DB_HOST=$(fetch db-host)"
  echo "DB_PORT=$(fetch db-port)"
  echo "DB_NAME=$(fetch db-name)"
  echo "DB_USER=$(fetch platform-db-user)"
  echo "DB_PASSWORD=$(fetch platform-db-password)"
  echo "DATABASE_URL=postgres://$(fetch platform-db-user):$(fetch platform-db-password)@$(fetch db-host):$(fetch db-port)/$(fetch db-name)"
  echo "FIREBASE_PROJECT_ID=$(fetch firebase-project-id)"
  echo "CORS_ORIGINS=$${PLATFORM_CORS_ORIGINS}"
} > /etc/sweptlock/platform.env
chmod 600 /etc/sweptlock/platform.env

# Write and render the platform NGINX proxy config (private binding only)
# $${PRIVATE_BIND_IP} escapes Terraform interpolation → ${PRIVATE_BIND_IP} at runtime → envsubst fills it in
cat > /etc/sweptlock/platform-proxy.conf.template << 'NGINXTEMPLATE'
server {
    listen ${PRIVATE_BIND_IP}:8080;

    location / {
        proxy_pass       http://platform-panel:80;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location /api/ {
        proxy_pass       http://platform-api:5001;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 30s;
    }
}
NGINXTEMPLATE

PRIVATE_BIND_IP="$${PRIVATE_BIND_IP}" \
  envsubst '${PRIVATE_BIND_IP}' \
  < /etc/sweptlock/platform-proxy.conf.template \
  > /etc/sweptlock/platform-proxy.conf

gcloud secrets versions access latest \
  --secret="$${PREFIX}-firebase-admin-sdk-json" \
  --project="$${PROJECT}" 2>/dev/null \
  > /etc/sweptlock/serviceAccountKey.json || true
chmod 644 /etc/sweptlock/serviceAccountKey.json

echo ">>> Secrets written."

# Pull images only if not already cached (skips on reboot if image exists)
gcloud auth configure-docker "$${REGION}-docker.pkg.dev" --quiet
docker image inspect "$${IMAGE}"               &>/dev/null || docker pull "$${IMAGE}"
docker image inspect "$${WEB_IMAGE}"           &>/dev/null || docker pull "$${WEB_IMAGE}"
docker image inspect "$${PLATFORM_API_IMAGE}"  &>/dev/null || docker pull "$${PLATFORM_API_IMAGE}"
docker image inspect "$${PLATFORM_PANEL_IMAGE}" &>/dev/null || docker pull "$${PLATFORM_PANEL_IMAGE}"

# Shared network so nginx can proxy to sweptlock-api by container name
docker network create sweptlock 2>/dev/null || true

# Recreate containers so they pick up the fresh env file
echo ">>> Starting API container..."
docker stop sweptlock-api 2>/dev/null || true
docker rm   sweptlock-api 2>/dev/null || true
docker run -d \
  --name sweptlock-api \
  --network sweptlock \
  --restart unless-stopped \
  --env-file /etc/sweptlock/env \
  -v /etc/sweptlock/serviceAccountKey.json:/app/serviceAccountKey.json:ro \
  "$${IMAGE}"

echo ">>> Starting web container..."
docker stop sweptlock-web 2>/dev/null || true
docker rm   sweptlock-web 2>/dev/null || true
docker run -d \
  --name sweptlock-web \
  --network sweptlock \
  --restart unless-stopped \
  -p 80:80 \
  "$${WEB_IMAGE}"

echo ">>> Starting platform-panel container..."
docker stop platform-panel 2>/dev/null || true
docker rm   platform-panel 2>/dev/null || true
docker run -d \
  --name platform-panel \
  --network sweptlock \
  --restart unless-stopped \
  "$${PLATFORM_PANEL_IMAGE}"

echo ">>> Starting platform-api container..."
docker stop platform-api 2>/dev/null || true
docker rm   platform-api 2>/dev/null || true
docker run -d \
  --name platform-api \
  --network sweptlock \
  --restart unless-stopped \
  --env-file /etc/sweptlock/platform.env \
  -v /etc/sweptlock/serviceAccountKey.json:/secrets/firebase-sa.json:ro \
  "$${PLATFORM_API_IMAGE}"

echo ">>> Starting platform-proxy container..."
docker stop sweptlock-platform-proxy 2>/dev/null || true
docker rm   sweptlock-platform-proxy 2>/dev/null || true
docker run -d \
  --name sweptlock-platform-proxy \
  --network sweptlock \
  --restart unless-stopped \
  -v /etc/sweptlock/platform-proxy.conf:/etc/nginx/conf.d/default.conf:ro \
  nginx:1.27-alpine

echo "=== Done: $(date) ==="
STARTSCRIPT

# Replace placeholders with real values (Terraform variables substituted here)
sed -i "s|__PROJECT__|${project_id}|g"             /usr/local/bin/sweptlock-start.sh
sed -i "s|__PREFIX__|${name_prefix}|g"             /usr/local/bin/sweptlock-start.sh
sed -i "s|__REGION__|${region}|g"                  /usr/local/bin/sweptlock-start.sh
sed -i "s|__IMAGE__|${image_url}|g"                /usr/local/bin/sweptlock-start.sh
sed -i "s|__WEB_IMAGE__|${web_image_url}|g"        /usr/local/bin/sweptlock-start.sh
sed -i "s|__PLATFORM_API_IMAGE__|${platform_api_image_url}|g"     /usr/local/bin/sweptlock-start.sh
sed -i "s|__PLATFORM_PANEL_IMAGE__|${platform_panel_image_url}|g" /usr/local/bin/sweptlock-start.sh
chmod +x /usr/local/bin/sweptlock-start.sh

# ── Write systemd service ─────────────────────────────────────────────────────
# Runs sweptlock-start.sh on every boot, after Docker is ready.
cat > /etc/systemd/system/sweptlock.service << 'SYSTEMD'
[Unit]
Description=Sweptlock — refresh secrets and run containers
After=docker.service network-online.target
Requires=docker.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/sweptlock-start.sh
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
SYSTEMD

systemctl daemon-reload
systemctl enable sweptlock.service

# Run immediately for first boot
echo ">>> Running sweptlock-start for first boot..."
/usr/local/bin/sweptlock-start.sh

echo "=== First-boot complete: $(date) ==="
