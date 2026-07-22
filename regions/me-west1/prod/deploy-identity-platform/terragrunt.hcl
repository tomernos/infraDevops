# Platform CI deploy identity — own state boundary, independent of the Engine deploy identity.
# Composition lives HERE (the live layer): concrete repo, roles, runtime SA, and descriptions are
# wired as inputs to the reusable modules/deploy-identity leaf.
#
# NOTE: this unit depends on the `platform` stack (sa-platform-api + sa-platform-panel must exist).
# Until the platform stack is applied in dev, this unit stays unapplied — its own state boundary means
# that does NOT block the Engine deploy identity.

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../modules/deploy-identity"
}

# The platform stack exposes two runtime SAs (sa-platform-api, sa-platform-panel); this deploy SA needs
# serviceAccountUser on both to deploy the Cloud Run services that run as them.
dependency "platform" {
  config_path = "../platform"
  mock_outputs = {
    platform_sa_email       = "swpt-mw1-prod-sa-platform-api@sweptlock-prod.iam.gserviceaccount.com"
    platform_panel_sa_email = "swpt-mw1-prod-sa-plat-panel@sweptlock-prod.iam.gserviceaccount.com"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
  # The platform stack is already applied, so terragrunt reads its REAL state outputs and would ignore
  # mock_outputs entirely — but platform_panel_sa_email doesn't exist in state until platform is
  # re-applied with the new panel SA. Shallow-merge mocks over state so the not-yet-present key falls
  # back to the mock at plan time (same pattern as dev/cloud-run). At apply, platform runs first (dep
  # graph) and the real output takes over.
  mock_outputs_merge_strategy_with_state = "shallow"
}

inputs = {
  name_prefix = "swpt-mw1-prod"
  component   = "plat"

  display_name = "Platform CI Deploy"
  description  = "GitHub Actions (SweptLock/Sweptlock-Platform): push images + deploy the platform Cloud Run services"

  # EXACT case as GitHub emits in the OIDC attribute.repository claim (case-sensitive).
  # Verify against the real repo slug — a casing mismatch fails WIF auth silently.
  github_repo = "SweptLock/Sweptlock-Platform"

  project_roles = [
    "roles/artifactregistry.writer", # push container images
    "roles/run.developer",           # deploy Cloud Run services/revisions
  ]

  # The platform runs its two Cloud Run services as two SEPARATE runtime SAs (api → sa-platform-api,
  # panel → sa-platform-panel). A Cloud Run deploy requires serviceAccountUser (actAs) on the runtime
  # SA of the revision it creates — even when --service-account is unchanged — so this deploy SA needs
  # actAs on BOTH sa-platform-api and sa-platform-panel.
  act_as_service_accounts = [
    dependency.platform.outputs.platform_sa_email,
    dependency.platform.outputs.platform_panel_sa_email,
  ]
}
