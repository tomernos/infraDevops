#!/usr/bin/env bash
# setup-wif.sh — create Workload Identity Federation + Terraform CI service accounts.
# Run once per project from WSL. Outputs the 3 values to paste as GitHub Secrets.
# Usage: ./scripts/setup-wif.sh
set -euo pipefail

PROJECT_ID="cryptoshare-e5172"
PROJECT_NUMBER="261111886016"
GITHUB_ORG="tomernos"
INFRA_REPO="infraDevops"

POOL_NAME="github-pool"
PROVIDER_NAME="github-provider"

SA_PLAN="sa-github-tf-plan"
SA_APPLY="sa-github-tf-apply"

SA_PLAN_EMAIL="${SA_PLAN}@${PROJECT_ID}.iam.gserviceaccount.com"
SA_APPLY_EMAIL="${SA_APPLY}@${PROJECT_ID}.iam.gserviceaccount.com"

echo "=== Setting up Workload Identity Federation for GitHub Actions ==="
echo "  project : $PROJECT_ID"
echo "  repo    : $GITHUB_ORG/$INFRA_REPO"
echo ""

gcloud config set project "$PROJECT_ID"

# ── Enable required API ───────────────────────────────────────────────────────
echo ">>> Enabling IAM Credentials API..."
gcloud services enable iamcredentials.googleapis.com --quiet

# ── Create WIF pool ───────────────────────────────────────────────────────────
if gcloud iam workload-identity-pools describe "$POOL_NAME" \
    --location=global --project="$PROJECT_ID" &>/dev/null; then
  echo ">>> Pool already exists — skipping."
else
  gcloud iam workload-identity-pools create "$POOL_NAME" \
    --project="$PROJECT_ID" \
    --location=global \
    --display-name="GitHub Actions"
  echo ">>> Pool created."
fi

# ── Create WIF provider ───────────────────────────────────────────────────────
if gcloud iam workload-identity-pools providers describe "$PROVIDER_NAME" \
    --workload-identity-pool="$POOL_NAME" \
    --location=global --project="$PROJECT_ID" &>/dev/null; then
  echo ">>> Provider already exists — skipping."
else
  gcloud iam workload-identity-pools providers create-oidc "$PROVIDER_NAME" \
    --project="$PROJECT_ID" \
    --location=global \
    --workload-identity-pool="$POOL_NAME" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.actor=assertion.actor" \
    --attribute-condition="assertion.repository == '${GITHUB_ORG}/${INFRA_REPO}'"
  echo ">>> Provider created."
fi

POOL_RESOURCE="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_NAME}"
PRINCIPAL_SET="principalSet://iam.googleapis.com/${POOL_RESOURCE}/attribute.repository/${GITHUB_ORG}/${INFRA_REPO}"

# ── Create service accounts (idempotent) ─────────────────────────────────────
for SA_NAME in "$SA_PLAN" "$SA_APPLY"; do
  SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
  if gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT_ID" &>/dev/null; then
    echo ">>> $SA_NAME already exists."
  else
    LABEL="${SA_NAME/sa-github-/GitHub CI — }"
    gcloud iam service-accounts create "$SA_NAME" \
      --display-name="$LABEL" --project="$PROJECT_ID"
    echo ">>> $SA_NAME created."
  fi
done

# ── Grant roles ───────────────────────────────────────────────────────────────
echo ">>> Granting roles..."

grant() {
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$1" --role="$2" \
    --condition=None --quiet
  echo "  OK  $1 → $2"
}

# Plan SA: read-only view of all resources + state bucket access
grant "$SA_PLAN_EMAIL" "roles/viewer"
gcloud storage buckets add-iam-policy-binding "gs://swpt-mw1-infra-sandbox-tf" \
  --member="serviceAccount:$SA_PLAN_EMAIL" \
  --role="roles/storage.objectAdmin" --quiet
echo "  OK  $SA_PLAN_EMAIL → state bucket objectAdmin"

# Apply SA: full control (sandbox only — use granular roles for prod)
grant "$SA_APPLY_EMAIL" "roles/owner"

# ── Bind SAs to WIF pool ──────────────────────────────────────────────────────
echo ">>> Binding SAs to WIF pool..."
for SA_EMAIL in "$SA_PLAN_EMAIL" "$SA_APPLY_EMAIL"; do
  gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
    --project="$PROJECT_ID" \
    --role="roles/iam.workloadIdentityUser" \
    --member="$PRINCIPAL_SET" \
    --quiet
  echo "  OK  $SA_EMAIL"
done

# ── Print GitHub Secrets ──────────────────────────────────────────────────────
WIF_PROVIDER_VALUE="${POOL_RESOURCE}/providers/${PROVIDER_NAME}"

echo ""
echo "=== Done. Add these 3 secrets to GitHub ==="
echo ""
echo "Repo: https://github.com/${GITHUB_ORG}/${INFRA_REPO}/settings/secrets/actions"
echo ""
echo "  WIF_PROVIDER          = ${WIF_PROVIDER_VALUE}"
echo "  SA_CI_TF_PLAN_EMAIL   = ${SA_PLAN_EMAIL}"
echo "  SA_CI_TF_APPLY_EMAIL  = ${SA_APPLY_EMAIL}"
echo ""
