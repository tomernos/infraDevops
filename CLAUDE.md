# sweptlock-infra — Claude Context

## What this repo is

Terraform + Terragrunt infrastructure for Sweptlock on GCP.

## Critical: Terragrunt v1.0 syntax

This repo is pinned to Terragrunt **v1.0**. Use the v1.0 command syntax:

```bash
# CORRECT (v1.0)
terragrunt run --all apply --non-interactive
terragrunt run --all plan --non-interactive

# WRONG (v0.x — will error)
terragrunt run-all apply
```

Root config file is `root.hcl` (not `terragrunt.hcl`).
All commands must run from **WSL Ubuntu** terminal. Not Git Bash.

## Quick facts

| | |
|---|---|
| GCP Project (dev) | `sweptlock-dev-844f2` |
| Region | `me-west1` (Tel Aviv) |
| State bucket | `swpt-mw1-infra-dev-tf` |
| Cloud Run service | `swpt-mw1-dev-api` |
| Image registry | `me-west1-docker.pkg.dev/sweptlock-dev-844f2/swpt-mw1-dev-registry/api` |
| App repo | `github.com/SweptLock/sweptlock-engine` |

## Architecture: Cloud Run + Firebase Hosting

- **Backend**: Cloud Run V2, Direct VPC Egress, Secret Manager env vars, scale-to-zero
- **Frontend**: Firebase Hosting (static Expo web export)
- **Database**: Cloud SQL PostgreSQL (private IP in VPC, no public IP)
- **Secrets**: Secret Manager only — no env files on any machine
- **Auth**: Workload Identity Federation — no JSON service account keys in CI

```
GitHub Actions
  → WIF (OIDC) → SA ci-deploy
  → docker push → Artifact Registry
  → gcloud run deploy → Cloud Run V2
                            ↓ Direct VPC Egress
                         Cloud SQL (private IP)
```

## Apply order

```
security → registry → networking → database → workload-identity → cloud-run
```

Note: `security` module has KMS import blocks. On first apply:
1. Comment out the import blocks
2. Apply once to create the KMS key ring + key
3. Uncomment the import blocks
4. Apply again to import into Terraform state

## Bootstrap (one-time per environment)

```bash
./scripts/bootstrap.sh dev
```

This creates the GCS state bucket, WIF pool, service accounts, and IAM bindings.
Run as a human GCP Owner before any Terraform work.

## Post-infra: populate secrets

After `database` apply, push secrets into Secret Manager:

```bash
./scripts/populate-secrets.sh
```

Then copy WIF outputs to GitHub Secrets:
- `WIF_PROVIDER_DEV` — from workload-identity Terraform output
- `SA_CI_DEPLOY_DEV` — from workload-identity Terraform output
- `FIREBASE_SERVICE_ACCOUNT_SWEPTLOCK_DEV` — download from Firebase Console

## Makefile shortcuts

```bash
make plan ENV=dev           # plan all stacks
make apply ENV=dev          # apply all stacks (ordered by deps)
make apply-cloud-run ENV=dev # apply single stack
make populate-secrets       # push secrets from .env into Secret Manager
make logs ENV=dev           # tail Cloud Run logs
make health ENV=dev         # curl health endpoint
```

## Non-negotiable

- Run `terragrunt plan` before every `apply`
- Never commit secrets or `.env` files
- All secrets go to Secret Manager — never in plaintext anywhere
- The `lifecycle { ignore_changes = [image] }` block on Cloud Run lets CI own image
  updates while Terraform owns everything else (env vars, scaling, VPC)
