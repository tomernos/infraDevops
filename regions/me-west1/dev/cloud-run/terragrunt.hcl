include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../modules/cloud-run"
}

dependency "security" {
  config_path = "../security"
  mock_outputs = {
    sa_api_email             = "mock-sa@mock-project.iam.gserviceaccount.com"
    kms_trust_dek_id         = "projects/mock/locations/me-west1/keyRings/mock-kr/cryptoKeys/mock-key"
    kms_sign_hmac_version_id = "projects/mock/locations/me-west1/keyRings/mock-kr/cryptoKeys/mock-mac/cryptoKeyVersions/1"
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

inputs = {
  name_prefix       = "swpt-mw1-dev"
  sa_api_email      = dependency.security.outputs.sa_api_email
  vpc_network       = dependency.networking.outputs.vpc_id
  subnetwork        = dependency.networking.outputs.subnet_id
  max_instances     = 3
  kek_kms_key       = dependency.security.outputs.kms_trust_dek_id
  sign_hmac_kms_key = dependency.security.outputs.kms_sign_hmac_version_id
}
