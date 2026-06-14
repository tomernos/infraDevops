include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../modules/workload-identity"
}

dependency "security" {
  config_path = "../security"
  mock_outputs = {
    sa_api_email = "mock-sa@mock-project.iam.gserviceaccount.com"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

inputs = {
  name_prefix  = "swpt-mw1-dev"
  github_owner = "tomernos"
  # app repo owner may differ from infra owner
  app_github_owner = "SweptLock"
  app_repo     = "sweptlock-engine"
  infra_repo   = "sweptlock-infra"
  state_bucket = "swpt-mw1-infra-dev-tf"
  sa_api_email = dependency.security.outputs.sa_api_email
}

# After apply, copy these outputs into GitHub Secrets for the sweptlock-engine repo:
#   WIF_PROVIDER_DEV      = outputs.wif_provider
#   SA_CI_DEPLOY_DEV      = outputs.sa_ci_deploy_email
