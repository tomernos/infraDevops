# Platform CI deploy identity — own state boundary, independent of the Engine deploy identity.
# Composition lives HERE (the live layer): concrete repo, roles, runtime SA, and descriptions are
# wired as inputs to the reusable modules/deploy-identity leaf.
#
# NOTE: this unit depends on the `platform` stack (sa-platform must exist). Until the platform stack
# is applied in dev, this unit stays unapplied — its own state boundary means that does NOT block
# the Engine deploy identity.

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../modules/deploy-identity"
}

# sa-platform (platform runtime SA shared by platform-api + panel) — this deploy SA needs
# serviceAccountUser on it to deploy the platform Cloud Run services that run as sa-platform.
dependency "platform" {
  config_path = "../platform"
  mock_outputs = {
    platform_sa_email = "swpt-mw1-dev-sa-platform@sweptlock-dev-844f2.iam.gserviceaccount.com"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

inputs = {
  name_prefix = "swpt-mw1-dev"
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

  act_as_service_accounts = [dependency.platform.outputs.platform_sa_email]
}
