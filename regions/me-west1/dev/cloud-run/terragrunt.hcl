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

# Forensic watermark service — applied (gate G2), running the real image. Its internal URL is injected
# into the API as WATERMARK_SVC_URL; the shared secret container it created is mounted below.
dependency "watermark" {
  config_path = "../watermark"
  mock_outputs = {
    uri = "https://mock-watermark-exqbi4quaq-zf.a.run.app"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
  mock_outputs_merge_strategy_with_state  = "shallow"
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

  # Guest sharing (Drop-Zone + Secure Outbound Share). Injects QUARANTINE_BUCKET +
  # DROP_ZONE_JWT_SECRET on the API. cleanup_scheduler_sa is the CONVENTIONAL name of the SA the
  # guest-sharing unit creates — passed as a constant (not a dependency output) so the engine→
  # guest-sharing edge stays one-directional (no cycle). See plans/gusturl-infra-plan.md.
  enable_guest_sharing = true
  cleanup_scheduler_sa = "swpt-mw1-dev-sa-cleanup@sweptlock-dev-844f2.iam.gserviceaccount.com"

  # Forensic watermark wiring (PR B): point the API's ForensicWatermarkProvider at the internal
  # watermark service and mount the shared X-WM-Auth secret (container created by the watermark unit,
  # value injected out-of-band). Empty defaults keep this dormant; setting them activates the forensic
  # path. The watermark service is IAM-locked to sa-api (primary gate); the secret is the app-owned second gate.
  watermark_svc_url            = dependency.watermark.outputs.uri
  watermark_shared_secret_name = "watermark-shared-secret"

  # Right-to-be-Forgotten sweeper: the conventional SA the account-lifecycle unit creates (constant,
  # not a dependency output, to keep the DAG acyclic). Without it /internal/run-deletion-sweep
  # rejects every call and requested deletions are never carried out.
  deletion_sweeper_sa = "swpt-mw1-dev-sa-del-sweep@sweptlock-dev-844f2.iam.gserviceaccount.com"

  # Auth/MFA epic. These were first set by hand on 2026-09-25 (revision 00080-shz) and are adopted
  # here so an apply of this unit no longer silently drops them.
  # AUTH_CONTACT_CUTOVER_DATE is FROZEN: it must equal the --cutover the contact-compliance
  # backfill was applied with. Never edit or remove it (removal re-opens unverified signups).
  auth_contact_cutover_date = "2026-09-25T14:38:28Z"
  app_web_base_url          = "https://sweptlock-dev-844f2.web.app"

  # PDF Sign external signers. Secret container adopted into the security unit (import block there);
  # its value was hand-injected 2026-09-16 and is mounted at `latest`.
  sign_guest_jwt_secret_name = "sign-guest-jwt-secret"
  # sign_link_base_url: PENDING the live value from `gcloud run services describe` (see PR body).
}
