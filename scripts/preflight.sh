#!/usr/bin/env bash
# preflight.sh — read-only pre-apply gate for LOCAL terragrunt runs.
#
# Local applies are the primary path while hosted Actions is budget-blocked, and
# every check below maps to a failure that actually burned an apply:
#   2026-07-22  ADC minted as the wrong account blocked the first prod apply
#   2026-07-22  `terragrunt run-all` (pre-1.x syntax) errors on the pinned CLI
#   2026-07-25  prod ci-runner Job created before its image existed -> Job FAILED
#   2026-07-30  ambient gcloud project = sweptlock-shared while planning prod
#   2026-07-30  bootstrap half-run left the apply SA with zero bindings
#   2026-07-30  shared state stamped by local terraform 1.12.2 vs the 1.9.8 pin
#
# Usage:   ./scripts/preflight.sh <env>        env = a dir under regions/me-west1/
#          make preflight ENV=<env>
#
# Runs ALL checks, then summarizes. Exits 1 if any FAIL. Never mutates GCP,
# state, or the repo. Portable to macOS bash 3.2 (the Mac runs these too).

set -u

REGION="${REGION:-me-west1}"
ENV_NAME="${1:-}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

if [ -z "$ENV_NAME" ] || [ ! -d "regions/$REGION/$ENV_NAME" ]; then
  echo "usage: $0 <env>   (env = one of: $(ls -m "regions/$REGION" 2>/dev/null))" >&2
  exit 2
fi

ENV_HCL="regions/$REGION/$ENV_NAME/env.hcl"
PROJECT_ID="$(grep -E 'project_id[[:space:]]*=' "$ENV_HCL" | sed -E 's/.*"([^"]+)".*/\1/' | head -1)"
if [ -z "$PROJECT_ID" ]; then
  echo "FATAL: could not parse project_id from $ENV_HCL" >&2
  exit 2
fi

PREFIX="swpt-mw1-$ENV_NAME"
BUCKET="swpt-mw1-infra-$ENV_NAME-tf"
FAILS=0
WARNS=0

pass() { printf 'PASS  %s\n' "$1"; }
warn() { printf 'WARN  %s\n' "$1"; WARNS=$((WARNS + 1)); }
fail() { printf 'FAIL  %s\n' "$1"; FAILS=$((FAILS + 1)); }
info() { printf 'info  %s\n' "$1"; }

echo "== preflight: env=$ENV_NAME project=$PROJECT_ID region=$REGION =="

# 1. Terraform binary vs the repo pin. State objects are stamped with the writer's
#    version; a newer local binary poisons state for the pinned CI (shared was
#    stamped 1.12.2 vs the 1.9.8 pin because nothing checked this).
PIN="$(cat .terraform-version 2>/dev/null)"
TF_V="$(terraform version 2>/dev/null | head -1 | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
if [ -z "$TF_V" ]; then
  fail "terraform not found on PATH"
elif [ "$TF_V" != "$PIN" ]; then
  fail "terraform $TF_V != repo pin $PIN (.terraform-version) — state written now will be refused by CI. Align before applying (install $PIN, or deliberately bump the pin repo-wide)."
else
  pass "terraform $TF_V matches pin"
fi

# 2. Terragrunt present and 1.x — the CLI renamed run-all to 'run --all'.
TG_V="$(terragrunt --version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
if [ -z "$TG_V" ]; then
  fail "terragrunt not found on PATH"
elif [ "${TG_V%%.*}" -lt 1 ]; then
  fail "terragrunt $TG_V is pre-1.0 — repo targets $(cat .terragrunt-version 2>/dev/null) (run --all syntax)"
else
  pass "terragrunt $TG_V (use: terragrunt run --all <cmd> --non-interactive — NOT the old run-all)"
fi

# 3. gcloud auth actually works right now (catches expired sessions BEFORE a
#    multi-unit apply stalls mid-run on interactive reauth).
ACCOUNT="$(gcloud config get-value account 2>/dev/null)"
case "$ACCOUNT" in ""|"(unset)") ACCOUNT="";; esac
if [ -z "$ACCOUNT" ]; then
  fail "no active gcloud account — run: gcloud auth login"
elif ! gcloud auth print-access-token >/dev/null 2>&1; then
  fail "cannot mint an access token as $ACCOUNT (expired session) — run: gcloud auth login"
else
  pass "auth OK as $ACCOUNT (eyeball this — is it the right identity for $ENV_NAME?)"
fi

# 4. Ambient gcloud project must match the target env (2026-07-30: project was
#    left on sweptlock-shared while planning prod units).
CUR_PROJ="$(gcloud config get-value project 2>/dev/null)"
case "$CUR_PROJ" in ""|"(unset)") CUR_PROJ="";; esac
if [ "$CUR_PROJ" != "$PROJECT_ID" ]; then
  fail "gcloud project is '$CUR_PROJ', target env wants '$PROJECT_ID' — run: gcloud config set project $PROJECT_ID"
else
  pass "gcloud project = $PROJECT_ID"
fi

# 5. State bucket reachable — catches wrong project, dead billing, and missing
#    bootstrap in one shot. Pair with TG_BACKEND_REQUIRE_BOOTSTRAP=true below so
#    terragrunt fails closed instead of silently creating a bucket on a typo.
if gcloud storage buckets describe "gs://$BUCKET" >/dev/null 2>&1; then
  pass "state bucket gs://$BUCKET reachable"
else
  fail "state bucket gs://$BUCKET not reachable — wrong project/auth, or bootstrap.sh $ENV_NAME never ran"
fi

# 6. If this env has a ci-runner unit, the runner image must already exist:
#    Cloud Run Job creation validates image pullability (prod Job sat FAILED from
#    07-25 because the apply ran before any image was published).
if [ -d "regions/$REGION/$ENV_NAME/ci-runner" ]; then
  RUNNER_IMG="$REGION-docker.pkg.dev/$PROJECT_ID/$PREFIX-registry/runner:latest"
  if gcloud artifacts docker images describe "$RUNNER_IMG" --project "$PROJECT_ID" >/dev/null 2>&1; then
    pass "runner image exists: $RUNNER_IMG"
  else
    fail "runner image MISSING: $RUNNER_IMG — publish it first (see regions/me-west1/shared/README.md 'Publishing the runner image'), THEN apply ci-runner. Order: registry apply -> image push -> ci-runner apply."
  fi
fi

# 7. Bootstrap completeness (warn-only): a half-run of bootstrap.sh can leave the
#    CI apply SA with zero bindings; local Owner applies hide it until the first
#    CI apply dies (observed on shared, 2026-07-30).
APPLY_SA="$PREFIX-sa-tf-apply@$PROJECT_ID.iam.gserviceaccount.com"
ROLES_N="$(gcloud projects get-iam-policy "$PROJECT_ID" \
  --flatten='bindings[].members' \
  --filter="bindings.members:serviceAccount:$APPLY_SA" \
  --format='value(bindings.role)' 2>/dev/null | grep -c . || true)"
if [ -z "$ROLES_N" ] || [ "$ROLES_N" = "0" ]; then
  warn "apply SA $APPLY_SA has ZERO project bindings (or policy unreadable) — re-run ./scripts/bootstrap.sh $ENV_NAME and verify per shared/README.md before any CI-driven apply"
else
  pass "apply SA has $ROLES_N project role binding(s)"
fi

# Context notes (never fail):
ADC="$HOME/.config/gcloud/application_default_credentials.json"
if [ -f "$ADC" ]; then
  info "ADC file present ($(date -r "$ADC" '+%Y-%m-%d %H:%M' 2>/dev/null || echo 'mtime n/a')) — the GOOGLE_OAUTH_ACCESS_TOKEN export below overrides it, so a stale/mismatched ADC cannot bite"
fi
CACHES="$(find "regions/$REGION/$ENV_NAME" -maxdepth 3 -type d -name '.terragrunt-cache' 2>/dev/null | grep -c . || true)"
if [ -n "$CACHES" ] && [ "$CACHES" != "0" ]; then
  info "$CACHES .terragrunt-cache dir(s) under this env — after editing modules/, purge them or 'edits that don't take' will follow"
fi

echo "== result: $FAILS fail, $WARNS warn =="
if [ "$FAILS" -gt 0 ]; then
  echo "Fix the FAILs above before applying."
  exit 1
fi

cat <<EOF

Preflight clean. Canonical non-interactive local run (terragrunt 1.x):

  export TF_INPUT=false TF_IN_AUTOMATION=true
  export TG_NON_INTERACTIVE=true
  export TG_BACKEND_REQUIRE_BOOTSTRAP=true          # never auto-create a state bucket
  export GOOGLE_OAUTH_ACCESS_TOKEN=\$(gcloud auth print-access-token)   # ~1h TTL; covers provider + GCS backend
  cd regions/$REGION/$ENV_NAME
  terragrunt run --all plan --non-interactive
  terragrunt run --all apply --non-interactive -- -auto-approve

Token expired mid-run? Re-mint the export and rerun — state is already consistent.
EOF
