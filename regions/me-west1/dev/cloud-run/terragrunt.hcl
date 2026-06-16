include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../modules/cloud-run"
}

dependency "security" {
  config_path = "../security"
  mock_outputs = {
    sa_api_email = "mock-sa@mock-project.iam.gserviceaccount.com"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "networking" {
  config_path = "../networking"
  mock_outputs = {
    vpc_self_link    = "projects/mock/global/networks/mock-vpc"
    subnet_self_link = "projects/mock/regions/me-west1/subnetworks/mock-subnet"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

inputs = {
  name_prefix      = "swpt-mw1-dev"
  sa_api_email     = dependency.security.outputs.sa_api_email
  vpc_self_link    = dependency.networking.outputs.vpc_self_link
  subnet_self_link = dependency.networking.outputs.subnet_self_link
  max_instances    = 3
}
