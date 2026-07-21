# `regions/me-west1/prod/` — production environment

A production duplication of `../dev/` with prod hardening. **Config only — nothing
applied.** Bring-up steps: `PROD-BRINGUP.md`. Naming/branch/state conventions are
identical across engine/platform/infra (project `sweptlock-prod`, prefix
`swpt-mw1-prod`, state bucket `swpt-mw1-infra-prod-tf`; `main`→dev auto, `prod`→PROD gated).

## How the environment layering works (no duplicated backend config)
`root.hcl` (repo root) owns **all** state/provider wiring and derives it from the
env layer — **no module or stack hardcodes a backend**:
- State bucket = `swpt-${region_short}-infra-${env}-tf` → `swpt-mw1-infra-prod-tf` (auto).
- State prefix = `path_relative_to_include()` (per-stack, isolated).
- Provider `project`/`region` = `env.hcl` / `region.hcl`.
- **Each environment has its own state bucket → fully separate state.** dev and prod
  never share state.

**Audit results (this review):**
- `grep -rn 'remote_state|backend "gcs"' modules/` → **none.** Modules are backend-agnostic; `root.hcl` is the single source. ✓
- The only `bucket=` hits in modules are a *storage* bucket (guest-sharing quarantine) and `var.state_bucket` (a WIF **input**, not a backend) — not backend duplication. ✓
- Environment-specific values live only in `env.hcl` + each stack's `inputs` (sizing, names). Shared **module** logic is environment-agnostic (parameterized by `name_prefix`, `project_id`, tier, etc.). ✓
- **No circular dependencies** — the stack DAG is acyclic (see below); one-directional edges (engine→guest-sharing, cloud-run→guest-sharing) are kept acyclic on purpose by passing conventional SA names as constants instead of dependency outputs (documented inline).

## Components (apply order = dependency DAG; Terragrunt orders it)
```
security
  ├─ networking ──► database
  │              ├─ cloud-run ──► guest-sharing
  │              └─ platform ───► deploy-identity-platform
  ├─ private-ca ─► cloud-run   (cloud-run consumes the CAS pool name)
  ├─ registry
  ├─ activity-log
  ├─ watermark ──► deploy-identity-engine  (also needs security)
  └─ ci-runner
```
`cloud-run` now has two inbound edges (networking, private-ca); still acyclic.
| Stack | Purpose |
|---|---|
| `security` | KMS key ring + trust-DEK key + sign-HMAC key; runtime service accounts (`sa-api`, `sa-cleanup`, …) + IAM. Foundational. **Prod: no local-CA PEM secrets** (`enable_local_platform_ca_secrets=false`). |
| `networking` | VPC, private subnet, Cloud NAT, private service connection for Cloud SQL. |
| `registry` | Artifact Registry repo (`swpt-mw1-prod-registry`) for container images. |
| `database` | Cloud SQL Postgres (**prod: `db-custom-2-4096`, HA, PITR, 30d backups, `deletion_protection=true`**), private IP. |
| `cloud-run` | Engine API service (`swpt-mw1-prod-api`); wires KMS keys, VPC egress, guest-sharing env, and the Platform CA (**prod: `ca_provider="gcp_cas"`, `cas_ca_pool` from `private-ca`, `allow_local_ca=false`**). |
| `private-ca` | Google Certificate Authority Service — CA pool (ENTERPRISE) + self-signed root CA (HSM key) that issues end-entity PDF-signing certs; grants `sa-api` `certificateRequester`. Design: `prod-ca-architecture.md`. |
| `guest-sharing` | Drop-Zone quarantine bucket + CORS, ClamAV scanner (Eventarc), cleanup scheduler. |
| `activity-log` | Pub/Sub → Firestore operational activity feed + publisher/subscriber IAM. |
| `watermark` | Forensic watermark Cloud Run service (private + authed). |
| `deploy-identity-engine` | Engine CI deploy SA + WIF binding for `SweptLock/sweptlock-engine`; `actAs` on `sa-api` + `sa-watermark`. **Prod: also needs cross-project `artifactregistry.reader` on the dev registry for digest promotion (see engine `PRODUCTION.md`).** |
| `deploy-identity-platform` | Platform CI deploy SA + WIF for `SweptLock/Sweptlock-Platform`; `actAs` on the two platform runtime SAs. |
| `platform` | `platform-api` + `platform-panel` Cloud Run services (admin panel). |
| `ci-runner` | Self-hosted GitHub Actions runner (Cloud Run Job) for mobile/APK builds. |
| `env.hcl` | Environment metadata: `env=prod`, `project_id=sweptlock-prod`, DB sizing, Cloud Run scaling. |

## Prod ≠ dev deltas (already applied in these files)
See `PROD-BRINGUP.md` for the full table. Highlights: SQL HA+PITR+deletion_protection;
`app_env=prod`; **real CA (no local CA)** — design in `prod-ca-architecture.md`; Cloud Run
max 10; state bucket auto-isolated.

## Future: environment values move to a separate YAML values repo
Today `env.hcl` is the environment value layer (HCL). The intended evolution is a
**separate values repo** holding per-env YAML (e.g. `values/me-west1/prod.yaml`), so
values are reviewed/owned independently of module logic. The seam already exists and
the migration is localized:

- **Where:** `root.hcl` reads the env layer via
  `read_terragrunt_config(find_in_parent_folders("env.hcl"))`. To source YAML instead,
  change `env.hcl` to a thin shim:
  ```hcl
  # env.hcl (future)
  locals {
    values = yamldecode(file("${get_env("SWEPTLOCK_VALUES_DIR", "../../../../../sweptlock-values")}/me-west1/prod.yaml"))
    env        = local.values.env
    project_id = local.values.project_id
    # … the rest of the current locals, read from local.values …
  }
  ```
  `root.hcl` and every stack keep reading the same `locals` — **no module or stack
  change required.** Only `env.hcl` becomes a YAML loader.
- **Keep now:** HCL `env.hcl` (self-contained, applies today). Do the YAML split as a
  separate change once the values repo exists; it does not block prod bring-up.
- **Invariant:** module logic stays environment-agnostic either way — values in, logic out.
