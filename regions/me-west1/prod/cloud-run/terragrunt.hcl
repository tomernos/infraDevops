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
  name_prefix       = "swpt-mw1-prod"
  sa_api_email      = dependency.security.outputs.sa_api_email
  vpc_network       = dependency.networking.outputs.vpc_id
  subnetwork        = dependency.networking.outputs.subnet_id
  max_instances     = 10
  kek_kms_key       = dependency.security.outputs.kms_trust_dek_id
  sign_hmac_kms_key = dependency.security.outputs.kms_sign_hmac_version_id

  # ── PROD Platform CA — DECISION REQUIRED BEFORE APPLY ─────────────────────────
  # Dev runs the LOCAL dev CA (ca_provider="local", allow_local_ca=true) with two
  # PEM secrets seeded out-of-band. PROD MUST NOT use the local CA — allow_local_ca
  # stays FALSE, and the local PEM secrets are NOT created (security stack sets
  # enable_local_platform_ca_secrets=false). Wire ca_provider to your real prod CA
  # (e.g. Google Private CA / managed CA) per the CA design, then apply. Leaving the
  # sentinel will fail validation on purpose — a fail-safe, not a mistake.
  app_env        = "prod"
  ca_provider    = "REPLACE_WITH_PROD_CA_PROVIDER" # must not be "local"
  allow_local_ca = false

  # Guest sharing (Drop-Zone + Secure Outbound Share). Injects QUARANTINE_BUCKET +
  # DROP_ZONE_JWT_SECRET on the API. cleanup_scheduler_sa is the CONVENTIONAL name of the SA the
  # guest-sharing unit creates — passed as a constant (not a dependency output) so the engine→
  # guest-sharing edge stays one-directional (no cycle). See plans/gusturl-infra-plan.md.
  enable_guest_sharing = true
  cleanup_scheduler_sa = "swpt-mw1-prod-sa-cleanup@sweptlock-prod.iam.gserviceaccount.com"
}
