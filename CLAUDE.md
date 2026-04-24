# infraDevops — Claude Context

## What this repo is

Terraform + Terragrunt infrastructure for Sweptlock (internal codename: Aladin) on GCP.

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

## Full architecture reference

See `ReferencesContext/sweptlockinfra/architecture.md` for the complete reference:
- Folder structure and naming conventions
- Module breakdown (networking, security, database, registry, compute-vm)
- GCP project details
- Secrets management
- CI/CD pipeline
- Common operations
- Destroy notes

ReferencesContext is at `~/Desktop/PersonalGitProjects/ReferencesContext` on all machines.

## Quick facts

| | |
|---|---|
| GCP Project | `cryptoshare-e5172` |
| Region | `me-west1` (Tel Aviv) |
| State bucket | `swpt-mw1-infra-sandbox-tf` |
| VM name | `swpt-mw1-sandbox-api` |
| Container name | `sweptlock-api` |
| Aladin repo | `github.com/eladrz/Aladin` |

## Apply order

```
networking → security → registry → database → compute
```

## Non-negotiable

- Run `terragrunt plan` before every `apply`
- Never commit secrets or `.env` files
- All secrets go to Secret Manager — never on the VM filesystem as plaintext
