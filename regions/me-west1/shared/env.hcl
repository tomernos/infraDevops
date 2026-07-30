# Central shared-services project — CI runner COMPUTE only.
#
# Not an application environment: no SQL, no VPC, no KMS, no secrets, no Cloud Run service. Just an
# Artifact Registry for runner images and a Cloud Run Job that hosts a self-hosted GitHub runner.
# That is why this file carries none of dev/prod's sizing locals — root.hcl merges whatever is here
# into every stack's inputs, and there is nothing here to size.
#
# The load-bearing property: the runner is compute, NOT credentials. Pipelines running on it still
# authenticate per-job via GitHub OIDC → the TARGET env's WIF → that env's deploy SA. So centralizing
# the worker needs no new deploy-path IAM and grants this project no power over dev or prod.
#
# Design + bring-up runbook: ReferencesContext/sweptlock/plans/shared-runner-project-design.md
locals {
  env        = "shared"
  project_id = "sweptlock-shared"
}
