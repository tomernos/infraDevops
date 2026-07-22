include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../modules/guest-sharing"
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
    vpc_id    = "projects/mock/global/networks/mock-vpc"
    subnet_id = "projects/mock/regions/me-west1/subnetworks/mock-subnet"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# Cloud Scheduler's cleanup job targets the engine API, so the API must exist first. Eventarc
# targets the scanner (owned by THIS unit), so there is no reverse edge — the DAG stays acyclic.
dependency "cloud-run" {
  config_path = "../cloud-run"
  mock_outputs = {
    service_name = "swpt-mw1-prod-api"
    service_url  = "https://swpt-mw1-prod-api-mock.a.run.app"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

inputs = {
  name_prefix      = "swpt-mw1-prod"
  sa_api_email     = dependency.security.outputs.sa_api_email
  vpc_network      = dependency.networking.outputs.vpc_id
  subnetwork       = dependency.networking.outputs.subnet_id
  api_service_name = dependency.cloud-run.outputs.service_name
  api_service_uri  = dependency.cloud-run.outputs.service_url
}
