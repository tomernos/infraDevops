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

# Production Platform CA (Google CAS). Applies before cloud-run so the pool exists when the API
# boots and validates it. Acyclic: private-ca depends only on security. See prod-ca-architecture.md.
dependency "private_ca" {
  config_path = "../private-ca"
  mock_outputs = {
    ca_pool_name = "projects/sweptlock-prod/locations/me-west1/caPools/swpt-mw1-prod-ca-pool"
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

  # ── PROD Platform CA — Google Certificate Authority Service (CAS) ─────────────
  # PROD uses the real HSM-backed CA (never the extractable local dev CA): allow_local_ca stays
  # FALSE and the local PEM secrets are not created (security stack sets
  # enable_local_platform_ca_secrets=false). The engine's gcp_cas provider issues from the CAS
  # pool below; CAS_CA_POOL is injected from the private-ca stack. Design + rotation/revocation:
  # regions/me-west1/prod/prod-ca-architecture.md.
  app_env        = "prod"
  ca_provider    = "gcp_cas"
  allow_local_ca = false
  cas_ca_pool    = dependency.private_ca.outputs.ca_pool_name

  # Guest sharing (Drop-Zone + Secure Outbound Share). Injects QUARANTINE_BUCKET +
  # DROP_ZONE_JWT_SECRET on the API. cleanup_scheduler_sa is the CONVENTIONAL name of the SA the
  # guest-sharing unit creates — passed as a constant (not a dependency output) so the engine→
  # guest-sharing edge stays one-directional (no cycle). See plans/gusturl-infra-plan.md.
  enable_guest_sharing = true
  cleanup_scheduler_sa = "swpt-mw1-prod-sa-cleanup@sweptlock-prod.iam.gserviceaccount.com"

  # KEYLESS Firebase Admin: the org disables downloadable SA keys, so prod does NOT mount a
  # FIREBASE_ADMIN_SDK_JSON secret — the backend authenticates as the runtime SA via ADC. This also
  # grants the runtime SA firebaseauth.admin + datastore.user; the Firebase Storage bucket grant is
  # applied out-of-band after Firebase provisions the bucket. See wiki/04-infra/prod-infrastructure.md.
  firebase_use_adc = true
}
