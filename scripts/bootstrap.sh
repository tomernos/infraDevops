#!/usr/bin/env bash
# scripts/bootstrap.sh
#
# One-time bootstrap per environment — run by a human admin before the pipeline.
# Creates ONLY the auth plumbing Terraform itself needs to run, and which therefore cannot be
# Terraform-managed without a lock-yourself-out cycle:
#   - GCS state bucket + versioning
#   - Required GCP APIs
#   - Workload Identity Federation pool + GitHub OIDC provider   (TF federates THROUGH these)
#   - Terraform-runner SAs: sa-tf-plan (read-only PRs) + sa-tf-apply (merge-to-main)
#   - Their IAM role + WIF principal bindings
#
# NOT here: the per-component DEPLOY service accounts (engine, platform). Those are leaf workload
# identities applied BY sa-tf-apply and live in Terraform — modules/ci-identity (regions/<r>/<env>/
# ci-identity). Emails come from `terragrunt output` there, not from this script.
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

set -euo pipefail

ENV="${1:?Usage: ./scripts/bootstrap.sh <env>}"

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

# NOTE: plan SA keeps the -sa-ci-tf-plan id for now. Normalizing it to -sa-tf-plan (to match
# -sa-tf-apply) would rotate the infra repo's own CI secrets across 5 workflows — tracked as a
# separate follow-up, not bundled into the deploy-SA migration.
SA_PLAN="${PREFIX}-sa-ci-tf-plan"
SA_APPLY="${PREFIX}-sa-tf-apply"

# GitHub owner/repo names — MUST match the exact case GitHub emits in OIDC claims,
# because WIF principalSet bindings are exact-string matches.
# Infra CI repo of record: SweptLock/Sweptlock-Infra (private). The public
# tomernos/infraDevops mirror is NOT the CI repo and is not authorized here.
# APP_GITHUB_OWNER stays here only to widen the provider attribute-condition to the app owner;
# the per-repo deploy bindings (engine, platform) are Terraform-managed in modules/ci-identity.
GITHUB_OWNER="SweptLock"
APP_GITHUB_OWNER="SweptLock"
INFRA_REPO="Sweptlock-Infra"

SA_PLAN_EMAIL="${SA_PLAN}@${PROJECT_ID}.iam.gserviceaccount.com"
SA_APPLY_EMAIL="${SA_APPLY}@${PROJECT_ID}.iam.gserviceaccount.com"

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
echo "  SAs          : ${SA_PLAN}, ${SA_APPLY}"
echo ""
read -r -p "Continue? [y/N] " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

gcloud config set project "$PROJECT_ID" --quiet

# ── 1. APIs ───────────────────────────────────────────────────────────────────

section "GCP APIs"
info "Enabling APIs (may take ~60s on first run)..."
gcloud services enable \
  compute.googleapis.com \
  run.googleapis.com \
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

# Plan SA: read-only on the project (roles/viewer) but needs to read state AND
# acquire the GCS state lock during plan. Terraform/terragrunt writes a .tflock
# object even for `plan` and dependency `terraform output`, so objectViewer is
# not enough — objectUser grants get/list + create/delete (lock), nothing more.
# The SA stays roles/viewer on the project, so it still cannot mutate real infra.
bind_project "$SA_PLAN_EMAIL"  "roles/viewer"
bind_bucket  "$SA_PLAN_EMAIL"  "roles/storage.objectUser"
# Plan must REFRESH IAM-member resources (e.g. google_storage_bucket_iam_member on the
# quarantine bucket in guest-sharing). Refresh calls *.getIamPolicy, which roles/viewer does
# NOT include for GCS buckets → plan 403s on any bucket-IAM resource. securityReviewer is the
# read-only union of *.getIamPolicy across services (get, never set), so the plan SA can refresh
# any IAM binding while staying strictly non-mutating.
bind_project "$SA_PLAN_EMAIL"  "roles/iam.securityReviewer"

# Apply SA: editor + IAM admin + state full access.
# editor does NOT cover two things our modules need, so grant them explicitly:
#   - cloudkms.admin             → set IAM policy on the KMS trust-DEK key (security module)
#   - servicenetworking.networksAdmin → create the private services VPC peering (networking module)
# Use granular roles in staging/prod instead of editor.
bind_project "$SA_APPLY_EMAIL" "roles/editor"
bind_project "$SA_APPLY_EMAIL" "roles/resourcemanager.projectIamAdmin"
# editor cannot setIamPolicy on these resource types — grant the service admin role:
bind_project "$SA_APPLY_EMAIL" "roles/cloudkms.admin"               # KMS key IAM (security)
bind_project "$SA_APPLY_EMAIL" "roles/servicenetworking.networksAdmin" # VPC peering (networking)
bind_project "$SA_APPLY_EMAIL" "roles/artifactregistry.admin"       # repo IAM (registry)
bind_project "$SA_APPLY_EMAIL" "roles/run.admin"                    # service IAM/public-invoker (cloud-run)
bind_bucket  "$SA_APPLY_EMAIL" "roles/storage.admin"

# NOTE: the per-component DEPLOY SAs (engine, platform) and their roles / actAs / WIF bindings are
# Terraform-managed in modules/ci-identity — NOT here. sa-tf-apply (above) has the projectIamAdmin +
# serviceAccountAdmin needed to create them and bind their SA-level IAM on apply.

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

# Only the Terraform-runner SAs are bound here. Deploy-SA WIF bindings live in modules/ci-identity.
bind_wif "$SA_PLAN_EMAIL"   "$GITHUB_OWNER"     "$INFRA_REPO"
bind_wif "$SA_APPLY_EMAIL"  "$GITHUB_OWNER"     "$INFRA_REPO"
ok "WIF bindings done"

# ── 8. GitHub Secrets output ──────────────────────────────────────────────────

WIF_PROVIDER_FULL="${POOL_RESOURCE}/providers/${WIF_PROVIDER_ID}"

echo ""
echo "============================================================"
echo "  Bootstrap complete for ${ENV^^}"
echo "============================================================"
echo ""
echo "  Infra repo (${INFRA_REPO}) secrets — names UNCHANGED (match the infra tf-* workflows):"
echo ""
echo "    WIF_PROVIDER            = ${WIF_PROVIDER_FULL}    (repo-level)"
echo "    SA_CI_TF_PLAN_EMAIL     = ${SA_PLAN_EMAIL}    (repo-level)"
echo "    SA_CI_TF_APPLY_EMAIL    = ${SA_APPLY_EMAIL}    (Environment secret -> ${ENV})"
echo ""
echo "  Engine + Platform deploy secrets (new convention). Deploy SA emails are Terraform-managed"
echo "  in modules/ci-identity — read them AFTER 'terragrunt apply' of the ci-identity stack:"
echo ""
echo "    Engine repo (sweptlock-engine):"
echo "      GCP_WIF_PROVIDER_${ENV^^}       = ${WIF_PROVIDER_FULL}"
echo "      GCP_SA_ENGINE_DEPLOY_${ENV^^}   = \$(terragrunt output -raw engine_deploy_sa_email)"
echo ""
echo "    Platform repo (Sweptlock-Platform):"
echo "      GCP_WIF_PROVIDER_${ENV^^}       = ${WIF_PROVIDER_FULL}"
echo "      GCP_SA_PLATFORM_DEPLOY_${ENV^^} = \$(terragrunt output -raw platform_deploy_sa_email)"
echo ""
