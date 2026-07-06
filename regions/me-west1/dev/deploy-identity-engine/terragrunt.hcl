# Engine CI deploy identity — own state boundary.
# Composition lives HERE (the live layer): concrete repo, roles, runtime SA, and descriptions are
# wired as inputs to the reusable modules/deploy-identity leaf.

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../modules/deploy-identity"
}

# sa-api (engine backend runtime SA) — this deploy SA needs serviceAccountUser on it to deploy
# Cloud Run revisions that run as sa-api.
dependency "security" {
  config_path = "../security"
  mock_outputs = {
    sa_api_email = "swpt-mw1-dev-sa-api@sweptlock-dev-844f2.iam.gserviceaccount.com"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

inputs = {
  name_prefix = "swpt-mw1-dev"
  component   = "eng"

  display_name = "Engine CI Deploy"
  description  = "GitHub Actions (SweptLock/sweptlock-engine): push images + deploy the backend Cloud Run service"

  # EXACT case as GitHub emits in the OIDC attribute.repository claim (case-sensitive).
  github_repo = "SweptLock/sweptlock-engine"

  project_roles = [
    "roles/artifactregistry.writer", # push container images
    "roles/run.developer",           # deploy Cloud Run services/revisions
  ]

  act_as_service_accounts = [dependency.security.outputs.sa_api_email]
}
