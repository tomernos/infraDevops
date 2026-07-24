## What
<!-- One-line summary of what this PR changes -->

## Why
<!-- Link to issue or describe the motivation -->

Closes #

## Stacks touched
<!-- List every stack this PR modifies -->
- [ ] `regions/me-west1/{dev,prod}/security`
- [ ] `regions/me-west1/{dev,prod}/networking`
- [ ] `regions/me-west1/{dev,prod}/database`
- [ ] `regions/me-west1/{dev,prod}/registry`
- [ ] `regions/me-west1/{dev,prod}/cloud-run`
- [ ] `regions/me-west1/{dev,prod}/guest-sharing`
- [ ] `regions/me-west1/{dev,prod}/watermark`
- [ ] `regions/me-west1/{dev,prod}/activity-log`
- [ ] `regions/me-west1/{dev,prod}/deploy-identity-engine`
- [ ] `regions/me-west1/{dev,prod}/deploy-identity-platform`
- [ ] `regions/me-west1/{dev,prod}/platform`
- [ ] `regions/me-west1/{dev,prod}/ci-runner`
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
