# Engine CI deploy identity — own state boundary.
# Composition lives HERE (the live layer): concrete repo, roles, runtime SA, and descriptions are
# wired as inputs to the reusable modules/deploy-identity leaf.

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../modules/deploy-identity"
}

# Runtime SAs this deploy SA must impersonate (serviceAccountUser/actAs) to deploy Cloud Run
# revisions that run AS them:
#   - sa-api       → the engine backend service (swpt-mw1-dev-api)
#   - sa-watermark → the forensic watermark service (deploy-watermark.yml mints revisions run as it)
dependency "security" {
  config_path = "../security"
  mock_outputs = {
    sa_api_email = "swpt-mw1-dev-sa-api@sweptlock-dev-844f2.iam.gserviceaccount.com"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# Watermark runtime SA. deploy-watermark.yml (engine) runs `gcloud run services update`, which mints a
# revision that runs as sa-watermark → the engine deploy SA needs actAs on it too (else deploy fails at
# runtime with PERMISSION_DENIED iam.serviceaccounts.actAs, green at plan/TF time). The watermark unit
# is applied (gate G2); the mock keeps plan green if this ever runs before it in a fresh clone.
dependency "watermark" {
  config_path = "../watermark"
  mock_outputs = {
    sa_email = "swpt-mw1-dev-sa-watermark@sweptlock-dev-844f2.iam.gserviceaccount.com"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
  mock_outputs_merge_strategy_with_state  = "shallow"
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

  act_as_service_accounts = [
    dependency.security.outputs.sa_api_email,
    dependency.watermark.outputs.sa_email,
  ]
}
