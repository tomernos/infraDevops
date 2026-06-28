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
  # security is already applied (real state), but its NEW output kms_sign_hmac_version_id isn't
  # applied yet — merge the mock for that missing key during plan (apply uses the real value,
  # since security applies before this stack via the dependency edge).
  mock_outputs_merge_strategy_with_state = "shallow"
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

  # Stage B: wire the dev-only local Platform CA. The two PEM secrets (populated out-of-band in
  # Stage A) inject as PLATFORM_CA_CERT_PEM / PLATFORM_CA_KEY_PEM via secret_key_ref:latest.
  app_env        = "dev"
  ca_provider    = "local"
  allow_local_ca = true
}
