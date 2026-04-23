include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../modules/compute-vm"
}

dependency "networking" {
  config_path = "../networking"
  mock_outputs = {
    vpc_self_link = "projects/mock/global/networks/mock-vpc"
    subnet_self_link = "projects/mock/regions/me-west1/subnetworks/mock-subnet"
    vpc_id        = "projects/mock/global/networks/mock-vpc"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "security" {
  config_path = "../security"
  mock_outputs = {
    sa_api_email = "mock-sa@mock-project.iam.gserviceaccount.com"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "registry" {
  config_path = "../registry"
  mock_outputs = {
    image_base_url = "me-west1-docker.pkg.dev/mock-project/mock-registry"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  name_prefix      = "swpt-mw1-sandbox"
  machine_type     = "e2-standard-2"
  subnet_self_link = dependency.networking.outputs.subnet_self_link
  vpc_name         = "swpt-mw1-sandbox-vpc"
  sa_api_email     = dependency.security.outputs.sa_api_email
  image_url        = "${dependency.registry.outputs.image_base_url}/api:latest"
}
