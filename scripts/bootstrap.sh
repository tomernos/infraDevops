#!/usr/bin/env bash
# bootstrap.sh — run once per environment before terragrunt init
# Creates the GCS state bucket and enables all required GCP APIs.
# Usage: ./scripts/bootstrap.sh [project_id] [region] [env]
set -euo pipefail

PROJECT_ID="${1:-cryptoshare-e5172}"
REGION="${2:-me-west1}"
ENV="${3:-sandbox}"
TENANT="swpt"

case "$REGION" in
  me-west1)     REGION_SHORT="mw1" ;;
  europe-west4) REGION_SHORT="ew4" ;;
  us-central1)  REGION_SHORT="uc1" ;;
  *) echo "Unknown region: $REGION. Add it to the case statement."; exit 1 ;;
esac

BUCKET="${TENANT}-${REGION_SHORT}-infra-${ENV}-tf"

echo "=== Sweptlock Infrastructure Bootstrap ==="
echo "  project : $PROJECT_ID"
echo "  region  : $REGION  ($REGION_SHORT)"
echo "  env     : $ENV"
echo "  bucket  : $BUCKET"
echo ""

gcloud config set project "$PROJECT_ID"

echo ">>> Enabling APIs (this takes ~60s on first run)..."
gcloud services enable \
  compute.googleapis.com \
  sqladmin.googleapis.com \
  servicenetworking.googleapis.com \
  cloudkms.googleapis.com \
  secretmanager.googleapis.com \
  artifactregistry.googleapis.com \
  dns.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  sts.googleapis.com \
  logging.googleapis.com \
  monitoring.googleapis.com \
  cloudresourcemanager.googleapis.com \
  --project="$PROJECT_ID"
echo ">>> APIs enabled."

echo ">>> Creating Terraform state bucket: gs://$BUCKET"
if gcloud storage buckets describe "gs://$BUCKET" --project="$PROJECT_ID" &>/dev/null; then
  echo ">>> Bucket already exists — skipping creation."
else
  gcloud storage buckets create "gs://$BUCKET" \
    --project="$PROJECT_ID" \
    --location="$REGION" \
    --uniform-bucket-level-access
  gcloud storage buckets update "gs://$BUCKET" --versioning
  echo ">>> Bucket created with versioning enabled."
fi

echo ""
echo "=== Bootstrap complete ==="
echo ""
echo "Next steps:"
echo "  cd regions/me-west1/sandbox"
echo "  terragrunt run-all init"
echo "  terragrunt run-all plan"
