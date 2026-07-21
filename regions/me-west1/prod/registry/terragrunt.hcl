include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../modules/registry"
}

dependency "security" {
  config_path = "../security"
  mock_outputs = {
    sa_api_email = "mock-sa@mock-project.iam.gserviceaccount.com"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

inputs = {
  name_prefix  = "swpt-mw1-prod"
  sa_api_email = dependency.security.outputs.sa_api_email
}
