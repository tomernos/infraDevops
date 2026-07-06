# modules/deploy-identity

Reusable **leaf** module for a GitHub-Actions CI **deploy identity**: one service account that a
single GitHub repository may impersonate via Workload Identity Federation to push images and deploy
Cloud Run.

The module holds **no product knowledge** — component slug, repo, roles, actAs targets, and
descriptions are all inputs. Instantiate it once per deployable component from a Terragrunt live unit
(one unit = one component = one state boundary). See
`ReferencesContext/sweptlock/wiki/adr-ci-deploy-identity.md` for the design rationale.

## What it creates

- `google_service_account` — `<name_prefix>-sa-<component>-deploy`
- `google_project_iam_member` — one per `project_roles` entry
- `google_service_account_iam_member` (actAs) — `roles/iam.serviceAccountUser` on each
  `act_as_service_accounts` runtime SA (so a Cloud Run deploy may run as it)
- `google_service_account_iam_member` (WIF) — repo-scoped `roles/iam.workloadIdentityUser` for
  `principalSet://…/attribute.repository/<github_repo>`

The WIF **pool + provider** are NOT managed here (they are bootstrap-owned auth plumbing); the module
only derives the pool's full resource name from the project number + `wif_pool_id`.

## Inputs

| Name | Required | Description |
|---|---|---|
| `project_id` | yes | GCP project id |
| `name_prefix` | yes | e.g. `swpt-mw1-dev` |
| `component` | yes | 2–5 lowercase alphanumerics, e.g. `eng`, `plat` |
| `display_name` | yes | SA display name (product-specific — from the live unit) |
| `description` | yes | SA description (product-specific — from the live unit) |
| `github_repo` | yes | `owner/repo`, EXACT case as GitHub emits `attribute.repository` |
| `project_roles` | yes | least-privilege project roles for the workflow |
| `act_as_service_accounts` | no | runtime SA emails the deploy SA must `actAs` (default `[]`) |
| `wif_pool_id` | no | WIF pool short id (default `<name_prefix>-wif-pool`) |

## Outputs

`sa_email`, `sa_account_id`.

## Example (Terragrunt live unit)

```hcl
terraform { source = "../../../../modules/deploy-identity" }

dependency "security" { config_path = "../security" }

inputs = {
  name_prefix             = "swpt-mw1-dev"
  component               = "eng"
  display_name            = "Engine CI Deploy"
  description             = "GitHub Actions (SweptLock/sweptlock-engine): push images + deploy backend"
  github_repo             = "SweptLock/sweptlock-engine"
  project_roles           = ["roles/artifactregistry.writer", "roles/run.developer"]
  act_as_service_accounts = [dependency.security.outputs.sa_api_email]
}
```
