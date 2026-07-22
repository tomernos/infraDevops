# Production bring-up — `sweptlock-prod` (me-west1)

> **✅ APPLIED 2026-07-22** — all core stacks are up (local `terragrunt run --all apply`, excluding
> ci-runner). Services run **hello seed images** (real app not deployed yet). Canonical prod state +
> the full first-apply issue/fix log live in the wiki:
> `ReferencesContext/sweptlock/wiki/prod-infrastructure.md` and `.../prod-bringup-record.md`.
> The steps below are the original runbook, kept for the next environment (staging). Deltas learned
> during the real apply (missing APIs, deletion_protection/stale-cache, `run --all` CLI, hello images,
> generator-less secrets) are captured in the bring-up record.

This is a **duplication of dev** (`regions/me-west1/dev/`) with production hardening.
The Terragrunt config in this folder is ready; what remains is the sequence of
**human-run, credential-gated steps** below (create project, bootstrap auth, fill
two decisions, apply, seed secrets, wire Firebase + CI).

> Project id: **`sweptlock-prod`** (already the `prod` case in `scripts/bootstrap.sh`).
> If GCP rejects it as taken, pick a unique id and change it in `env.hcl` **and**
> `scripts/bootstrap.sh`'s `prod` case, then re-run `grep -rl sweptlock-prod` here.

## What differs from dev (prod hardening — already applied in these files)
| Setting | dev | **prod** |
|---|---|---|
| Cloud SQL tier | `db-g1-small` | `db-custom-2-4096` |
| SQL HA / PITR | off / off | **on / on** |
| SQL backups | 7 days | **30 days** |
| SQL `deletion_protection` | false | **true** |
| Cloud Run max instances | 3 | 10 (watermark 4) |
| Platform CA | `local` dev CA | **`gcp_cas` (CAS) — wired to the `private-ca` stack** |
| `app_env` | `dev` | `prod` |
| State bucket | `swpt-mw1-infra-dev-tf` | `swpt-mw1-infra-prod-tf` (auto) |
| Resource prefix | `swpt-mw1-dev` | `swpt-mw1-prod` |

## Before `apply`
**Platform CA is now wired** — `cloud-run/terragrunt.hcl` sets `ca_provider="gcp_cas"` with
`cas_ca_pool` from the new `private-ca` stack (CAS pool + self-signed root, HSM key,
`allow_local_ca=false`, no local PEM secrets). Design + rotation/revocation in
`prod-ca-architecture.md`. CA to-dos at apply time: ensure `privateca.googleapis.com` is enabled
(add to `bootstrap.sh` API list if missing), enable CAS **Data Access audit logs**, and
optionally set `CAS_ISSUING_CA` if you pin a subordinate CA.

### One decision you must still make before `apply`
1. **Platform image tags** — `platform/terragrunt.hcl` has
   `:REPLACE_WITH_PROD_TAG` for `api_image` / `panel_image`. For the first apply,
   build+push a prod image or temporarily point at a public hello image; the
   Platform deploy pipeline manages the digest afterward. (The engine backend image
   is managed entirely by `deploy-backend.yml`, no input here.)

Optional: `firebase_project_id` in `platform/terragrunt.hcl` defaults to
`sweptlock-prod` (consolidated like dev's 844f2). Change it if prod uses a separate
Firebase project.

---

## Steps

### 1. Create the project + billing (Owner)
```bash
gcloud projects create sweptlock-prod --name="SweptLock Prod"
gcloud billing projects link sweptlock-prod --billing-account="<BILLING_ACCOUNT_ID>"
```

### 2. Bootstrap the auth plumbing (idempotent)
Creates the state bucket, enables APIs, and creates the WIF pool/provider + the
`sa-tf-plan` / `sa-tf-apply` runner SAs. Nothing Terraform-managed.
```bash
cd sweptlock-infra
./scripts/bootstrap.sh prod        # authenticated as Owner of sweptlock-prod
```

### 3. Fill the remaining decision
- `regions/me-west1/prod/platform/terragrunt.hcl` → real image tags (or a hello image for apply #1).
- (CA already wired: `cloud-run` → `ca_provider="gcp_cas"` + `private-ca` stack. Confirm
  `privateca.googleapis.com` is enabled by `bootstrap.sh`.)

### 4. Create the `prod` GitHub Environment (approval gate)
In `SweptLock/Sweptlock-Infra` → Settings → Environments → **New: `prod`** →
add required reviewers. `tf-apply.yml` will not apply prod without this approval.

### 5. Apply the stacks (dependency order handled by Terragrunt)
Prefer the pipeline: **Actions → "Terraform Apply" → Run workflow → environment:
`prod`** (plans, waits for your `prod` Environment approval, then applies). Or locally:
```bash
cd regions/me-west1/prod
terragrunt run-all plan
terragrunt run-all apply
```
Dependency DAG (Terragrunt orders it): `security → networking →
{registry, database, watermark, activity-log} → cloud-run → guest-sharing →
deploy-identity-engine → platform → deploy-identity-platform → ci-runner`.

> **First-apply KMS caveat (security stack):** the KMS key ring/key don't exist yet
> in a fresh project. As the comment in `security/terragrunt.hcl` says, temporarily
> comment out both `import` blocks in `modules/security/main.tf`, apply, then
> uncomment and apply again (no-op). Same dance dev went through.

### 6. Seed Secret Manager (after `database` applies)
Reads the SQL private IP from the Cloud SQL API and the generated password from the
prod TF state object — only needs Owner gcloud auth.
```bash
cd sweptlock-infra
ENV=prod ./scripts/populate-secrets.sh sweptlock-prod swpt-mw1-prod
```
Provide prod values (not dev) for: DB app secrets, `DROP_ZONE_JWT_SECRET`,
`ADMIN_EMAIL`, Firebase bucket, and any KMS-key-version references. **KEK/sign-HMAC
are KMS-only** (no master key) — the cloud-run stack wires the KMS key ids from the
security stack automatically.

### 7. Firebase (Auth, Hosting, Storage)
Add Firebase to the prod project (or a separate Firebase project if chosen): enable
Google Sign-In, register the web app, set the Hosting target, and register the
release APK SHA-1 if mobile SSO targets prod. Capture the `EXPO_PUBLIC_FIREBASE_*`
config for the frontend `_PROD` secrets.

### 8. GitHub `_PROD` secrets (engine + platform deploy)
Grab the WIF provider + deploy-SA emails from Terragrunt outputs:
```bash
terragrunt -w regions/me-west1/prod/deploy-identity-engine   output   # engine deploy SA
terragrunt -w regions/me-west1/prod/deploy-identity-platform output   # platform deploy SA
```
Set repo secrets (mirroring the existing `_DEV` set) as `_PROD`:
`GCP_WIF_PROVIDER_PROD`, `GCP_SA_ENGINE_DEPLOY_PROD`,
`FIREBASE_SERVICE_ACCOUNT_SWEPTLOCK_PROD`, and the `EXPO_PUBLIC_*` prod values.

### 9. Prod deploy pipelines (engine repo — follow-up)
`deploy-backend.yml` / `deploy-frontend.yml` deploy **dev** on push to `main`. Add a
prod path — a manual `workflow_dispatch` targeting the prod service, or a `prod`
GitHub Environment + `_PROD` secrets — so a merge doesn't auto-ship to prod. Do this
**before** merging the app branch. Cloud Run service: `swpt-mw1-prod-api`; migrate
job: `swpt-mw1-prod-migrate` (mirrors the dev names).

### 10. DNS / domain
Point the prod domain at the prod Hosting + Cloud Run, and add it to `CORS_ORIGIN`
(exact-match allowlist — `*` is not a wildcard; see `backend/src/config/httpSecurity.js`).

---

## Verification checklist
- [ ] `gs://swpt-mw1-infra-prod-tf` exists (versioned) and holds state after apply.
- [ ] `swpt-mw1-prod-sql-main` is HA, PITR on, `deletion_protection` true.
- [ ] `swpt-mw1-prod-api` (Cloud Run) healthy: `/health` → `{"status":"ok"}`.
- [ ] KMS key ring/keys exist; cloud-run wired to `kms_trust_dek_id` + `kms_sign_hmac_version_id`.
- [ ] `ca_provider` is a real CA (NOT `local`); no local-CA PEM secrets in prod.
- [ ] migrate job ran (053–057 applied) before the first prod revision served.
- [ ] `_PROD` GitHub secrets set; prod deploy is manual/gated, not auto-on-merge.
