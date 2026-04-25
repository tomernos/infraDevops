## What
<!-- One-line summary of what this PR changes -->

## Why
<!-- Link to issue or describe the motivation -->

Closes #

## Stacks touched
<!-- List every stack this PR modifies -->
- [ ] `regions/me-west1/sandbox/networking`
- [ ] `regions/me-west1/sandbox/security`
- [ ] `regions/me-west1/sandbox/database`
- [ ] `regions/me-west1/sandbox/compute`
- [ ] `regions/me-west1/sandbox/registry`
- [ ] `regions/me-west1/sandbox/workload-identity`
- [ ] `regions/me-west1/sandbox/dns`
- [ ] `regions/me-west1/sandbox/observability`
- [ ] `modules/` (shared module change — affects all envs)

## Risk
- **Level**: Low / Medium / High
- **Blast radius**: _(what breaks if this goes wrong?)_
- **Rollback**: _(how to revert — `terraform apply` previous commit, manual step, etc.)_

## Plan output
<!-- CI posts this automatically — paste here only if running manually -->

## Checklist
- [ ] `terraform fmt` passes locally
- [ ] `tflint` passes locally
- [ ] No secrets or sensitive values hardcoded
- [ ] Destroy operations reviewed and intentional
- [ ] Module changes tested against sandbox before merging
