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
  name_prefix  = "swpt-mw1-sandbox"
  github_owner = "tomernos"
  app_repo     = "Aladin"
  infra_repo   = "sweptlock-infra"
  state_bucket = "swpt-mw1-infra-sandbox-tf"
  sa_api_email = dependency.security.outputs.sa_api_email
}
