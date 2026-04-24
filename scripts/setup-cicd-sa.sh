#!/usr/bin/env bash
# setup-cicd-sa.sh — create the GitHub CI service account with minimum required permissions.
# Run once per project. Outputs the JSON key to paste as GCP_SA_KEY in GitHub Secrets.
# Usage: ./scripts/setup-cicd-sa.sh [project_id]
set -euo pipefail

PROJECT_ID="${1:-cryptoshare-e5172}"
SA_NAME="sa-github-ci"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
KEY_FILE="/tmp/${SA_NAME}-key.json"

echo "=== Setting up GitHub CI service account ==="
echo "  project : $PROJECT_ID"
echo "  SA      : $SA_EMAIL"
echo ""

gcloud config set project "$PROJECT_ID"

# ── Create SA (idempotent) ────────────────────────────────────────────────────
if gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT_ID" &>/dev/null; then
  echo ">>> SA already exists — skipping creation."
else
  gcloud iam service-accounts create "$SA_NAME" \
    --display-name="GitHub CI — build and deploy" \
    --project="$PROJECT_ID"
  echo ">>> SA created."
fi

# ── Grant minimum required roles ─────────────────────────────────────────────
echo ">>> Granting roles..."

grant() {
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$SA_EMAIL" \
    --role="$1" \
    --condition=None \
    --quiet
  echo "  OK  $1"
}

grant "roles/artifactregistry.writer"    # push Docker images
grant "roles/compute.osLogin"            # SSH into VM via IAP
grant "roles/iap.tunnelResourceAccessor" # tunnel SSH through IAP
grant "roles/iam.serviceAccountUser"     # impersonate VM sa-api

# ── Export key ────────────────────────────────────────────────────────────────
echo ""
echo ">>> Generating JSON key → $KEY_FILE"
gcloud iam service-accounts keys create "$KEY_FILE" \
  --iam-account="$SA_EMAIL" \
  --project="$PROJECT_ID"

echo ""
echo "=== Done ==="
echo ""
echo "Next: add the following as GitHub Secret GCP_SA_KEY in the Aladin repo:"
echo "  https://github.com/tomernos/Aladin/settings/secrets/actions"
echo ""
echo "Key contents:"
cat "$KEY_FILE"
echo ""
echo "Also add these secrets:"
echo "  GCP_PROJECT_ID  = $PROJECT_ID"
echo "  GCP_REGION      = me-west1"
echo "  GCP_VM_NAME     = swpt-mw1-sandbox-api"
echo "  GCP_VM_ZONE     = me-west1-a"
echo "  REGISTRY_HOST   = me-west1-docker.pkg.dev"
echo "  IMAGE_PATH      = $PROJECT_ID/swpt-mw1-sandbox-registry/api"
