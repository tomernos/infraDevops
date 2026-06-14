#!/usr/bin/env bash
# scripts/bootstrap.sh
#
# One-time bootstrap per environment — run by a human admin before the pipeline.
# Creates everything the Terraform CI/CD pipeline needs to authenticate to GCP:
#   - GCS state bucket + versioning
#   - Required GCP APIs
#   - Workload Identity Federation pool + GitHub OIDC provider
#   - CI service accounts (plan, apply, deploy)
#   - IAM role bindings
#   - WIF principal bindings
#
# Nothing here is managed by Terraform. No imports. No state conflicts.
# Idempotent — safe to re-run.
#
# Prerequisites:
#   gcloud CLI installed and authenticated as project Owner
#
# Usage:
#   ./scripts/bootstrap.sh sandbox
#   ./scripts/bootstrap.sh staging
#   ./scripts/bootstrap.sh prod
#   ./scripts/bootstrap.sh sandbox <sa_api_email>
#
# sa_api_email: email of the app API SA (output of security module).
# Needed so ci-deploy can SSH to VMs running as sa-api.
# Omit on first run — re-run with it once the security module is applied.

set -euo pipefail

ENV="${1:?Usage: ./scripts/bootstrap.sh <env> [sa_api_email]}"
SA_API_EMAIL="${2:-}"

# ── Per-environment config ────────────────────────────────────────────────────

case "$ENV" in
  dev)     PROJECT_ID="sweptlock-dev-844f2" ;;
  staging) PROJECT_ID="sweptlock-staging" ;;
  prod)    PROJECT_ID="sweptlock-prod" ;;
  *) echo "Unknown env '${ENV}'. Valid: dev | staging | prod"; exit 1 ;;
esac

TENANT="swpt"
REGION="me-west1"
REGION_SHORT="mw1"
PREFIX="${TENANT}-${REGION_SHORT}-${ENV}"

# Matches root.hcl bucket formula: ${tenant}-${region_short}-infra-${env}-tf
STATE_BUCKET="${TENANT}-${REGION_SHORT}-infra-${ENV}-tf"

# Matches workload-identity module naming
WIF_POOL="${PREFIX}-wif-pool"
WIF_PROVIDER_ID="github"

SA_PLAN="${PREFIX}-sa-ci-tf-plan"
SA_APPLY="${PREFIX}-sa-tf-apply"
SA_DEPLOY="${PREFIX}-sa-ci-deploy"

GITHUB_OWNER="tomernos"
APP_GITHUB_OWNER="sweptlock"
APP_REPO="sweptlock-engine"
INFRA_REPO="infraDevops"

SA_PLAN_EMAIL="${SA_PLAN}@${PROJECT_ID}.iam.gserviceaccount.com"
SA_APPLY_EMAIL="${SA_APPLY}@${PROJECT_ID}.iam.gserviceaccount.com"
SA_DEPLOY_EMAIL="${SA_DEPLOY}@${PROJECT_ID}.iam.gserviceaccount.com"

# ── Helpers ───────────────────────────────────────────────────────────────────

info()    { echo "  >  $*"; }
ok()      { echo "  OK $*"; }
skip()    { echo "  -- already exists, skipped: $*"; }
section() { printf "\n== %s ==\n" "$*"; }

# ── Confirm ───────────────────────────────────────────────────────────────────

echo ""
echo "Bootstrap: ${ENV} -> ${PROJECT_ID}"
echo "  State bucket : gs://${STATE_BUCKET}"
echo "  WIF pool     : ${WIF_POOL}"
echo "  SAs          : ${SA_PLAN}, ${SA_APPLY}, ${SA_DEPLOY}"
echo ""
read -r -p "Continue? [y/N] " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

gcloud config set project "$PROJECT_ID" --quiet

# ── 1. APIs ───────────────────────────────────────────────────────────────────

section "GCP APIs"
info "Enabling APIs (may take ~60s on first run)..."
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
  --project="$PROJECT_ID" --quiet
ok "APIs enabled"

# ── 2. State bucket ───────────────────────────────────────────────────────────

section "GCS state bucket"
if gcloud storage buckets describe "gs://${STATE_BUCKET}" --project="$PROJECT_ID" &>/dev/null; then
  skip "gs://${STATE_BUCKET}"
else
  gcloud storage buckets create "gs://${STATE_BUCKET}" \
    --project="$PROJECT_ID" --location="$REGION" --uniform-bucket-level-access
  gcloud storage buckets update "gs://${STATE_BUCKET}" --versioning
  ok "gs://${STATE_BUCKET} (versioning on)"
fi

# ── 3. WIF pool ───────────────────────────────────────────────────────────────

section "Workload Identity pool"
if gcloud iam workload-identity-pools describe "$WIF_POOL" \
    --project="$PROJECT_ID" --location=global &>/dev/null; then
  skip "$WIF_POOL"
else
  gcloud iam workload-identity-pools create "$WIF_POOL" \
    --project="$PROJECT_ID" --location=global \
    --display-name="GitHub Actions" \
    --description="WIF pool for GitHub Actions — no JSON keys ever"
  ok "$WIF_POOL"
fi

# ── 4. WIF provider ───────────────────────────────────────────────────────────

section "GitHub OIDC provider"
if gcloud iam workload-identity-pools providers describe "$WIF_PROVIDER_ID" \
    --project="$PROJECT_ID" --location=global \
    --workload-identity-pool="$WIF_POOL" &>/dev/null; then
  skip "provider/${WIF_PROVIDER_ID}"
else
  gcloud iam workload-identity-pools providers create-oidc "$WIF_PROVIDER_ID" \
    --project="$PROJECT_ID" --location=global \
    --workload-identity-pool="$WIF_POOL" \
    --display-name="GitHub OIDC" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner,attribute.ref=assertion.ref" \
    --attribute-condition="assertion.repository_owner in ['${GITHUB_OWNER}', '${APP_GITHUB_OWNER}']"
  ok "provider/${WIF_PROVIDER_ID}"
fi

# ── 5. Service accounts ───────────────────────────────────────────────────────

section "Service accounts"

create_sa() {
  local ID="$1" DISPLAY="$2" DESC="$3"
  local EMAIL="${ID}@${PROJECT_ID}.iam.gserviceaccount.com"
  if gcloud iam service-accounts describe "$EMAIL" --project="$PROJECT_ID" &>/dev/null; then
    skip "$ID"
  else
    gcloud iam service-accounts create "$ID" \
      --project="$PROJECT_ID" --display-name="$DISPLAY" --description="$DESC"
    ok "$ID"
  fi
}

create_sa "$SA_PLAN"   "CI Terraform Plan"           "Read-only SA for terraform plan on infra PRs"
create_sa "$SA_APPLY"  "CI Terraform Apply ${ENV^}"  "Apply SA for ${ENV} infrastructure changes"
create_sa "$SA_DEPLOY" "CI Deploy"                   "Pushes images and deploys to VM via GitHub Actions"

# ── 6. IAM role bindings ──────────────────────────────────────────────────────

section "IAM role bindings"

bind_project() {
  info "$1 -> $2"
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$1" --role="$2" --condition=None --quiet
}

bind_bucket() {
  info "gs://${STATE_BUCKET} -> $1 -> $2"
  gcloud storage buckets add-iam-policy-binding "gs://${STATE_BUCKET}" \
    --member="serviceAccount:$1" --role="$2" --quiet
}

# Plan SA: viewer + state reader
bind_project "$SA_PLAN_EMAIL"  "roles/viewer"
bind_bucket  "$SA_PLAN_EMAIL"  "roles/storage.objectViewer"

# Apply SA: editor + IAM admin + state full access
# Use granular roles in staging/prod instead of editor
bind_project "$SA_APPLY_EMAIL" "roles/editor"
bind_project "$SA_APPLY_EMAIL" "roles/resourcemanager.projectIamAdmin"
bind_bucket  "$SA_APPLY_EMAIL" "roles/storage.admin"

# Deploy SA: image push + Cloud Run deploy
for ROLE in \
  "roles/artifactregistry.writer" \
  "roles/run.developer"; do
  bind_project "$SA_DEPLOY_EMAIL" "$ROLE"
done

# Deploy SA -> serviceAccountUser on sa-api (so Cloud Run can run as sa-api)
if [[ -n "$SA_API_EMAIL" ]]; then
  info "ci-deploy -> serviceAccountUser on $SA_API_EMAIL"
  gcloud iam service-accounts add-iam-policy-binding "$SA_API_EMAIL" \
    --project="$PROJECT_ID" \
    --role="roles/iam.serviceAccountUser" \
    --member="serviceAccount:${SA_DEPLOY_EMAIL}" --quiet
  ok "ci-deploy -> serviceAccountUser"
else
  echo ""
  echo "  NOTE: sa_api_email not provided — skipping ci-deploy -> sa-api binding."
  echo "  Re-run after the security module is applied:"
  echo "    ./scripts/bootstrap.sh ${ENV} <sa_api_email>"
fi

# ── 7. WIF principal bindings ─────────────────────────────────────────────────

section "WIF principal bindings"

PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')
POOL_RESOURCE="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL}"

bind_wif() {
  local SA_EMAIL="$1" OWNER="$2" REPO="$3"
  local PRINCIPAL="principalSet://iam.googleapis.com/${POOL_RESOURCE}/attribute.repository/${OWNER}/${REPO}"
  info "$SA_EMAIL <- ${OWNER}/${REPO}"
  gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
    --project="$PROJECT_ID" \
    --role="roles/iam.workloadIdentityUser" \
    --member="$PRINCIPAL" --quiet
}

bind_wif "$SA_PLAN_EMAIL"   "$GITHUB_OWNER"     "$INFRA_REPO"
bind_wif "$SA_APPLY_EMAIL"  "$GITHUB_OWNER"     "$INFRA_REPO"
bind_wif "$SA_DEPLOY_EMAIL" "$APP_GITHUB_OWNER" "$APP_REPO"
ok "WIF bindings done"

# ── 8. GitHub Secrets output ──────────────────────────────────────────────────

WIF_PROVIDER_FULL="${POOL_RESOURCE}/providers/${WIF_PROVIDER_ID}"

echo ""
echo "============================================================"
echo "  Bootstrap complete for ${ENV^^}"
echo "============================================================"
echo ""
echo "  Repo-level secrets  (Settings -> Secrets -> Actions):"
echo ""
echo "    WIF_PROVIDER          = ${WIF_PROVIDER_FULL}"
echo "    SA_CI_TF_PLAN_EMAIL   = ${SA_PLAN_EMAIL}"
echo ""
echo "  Environment secret  (Settings -> Environments -> ${ENV}):"
echo ""
echo "    SA_CI_TF_APPLY_EMAIL  = ${SA_APPLY_EMAIL}"
echo ""
echo "  App repo (${APP_REPO}) secrets (name them with _${ENV^^} suffix):"
echo ""
echo "    WIF_PROVIDER_${ENV^^}    = ${WIF_PROVIDER_FULL}"
echo "    SA_CI_DEPLOY_${ENV^^}    = ${SA_DEPLOY_EMAIL}"
echo ""
