# ── Service Accounts ─────────────────────────────────────────────────────────

resource "google_service_account" "sa_api" {
  account_id   = "${var.name_prefix}-sa-api"
  display_name = "Sweptlock API"
  description  = "Used by the backend VM / container to access GCP services"
  project      = var.project_id
}

resource "google_service_account" "sa_migrator" {
  account_id   = "${var.name_prefix}-sa-migrator"
  display_name = "Sweptlock DB Migrator"
  description  = "Narrow-permission SA for running database migrations"
  project      = var.project_id
}

# ── IAM Bindings for sa-api ──────────────────────────────────────────────────

locals {
  api_roles = [
    "roles/cloudsql.client",
    "roles/secretmanager.secretAccessor",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/artifactregistry.reader",
  ]
}

resource "google_project_iam_member" "api_roles" {
  for_each = toset(local.api_roles)
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.sa_api.email}"
}

resource "google_project_iam_member" "migrator_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.sa_migrator.email}"
}

# The CI Terraform-apply SA (created out-of-band by bootstrap.sh) manages service accounts AND
# their resource-level IAM (e.g. the ci-runner module's serviceAccountUser binding on sa-runner).
# Its bootstrap roles — roles/editor + roles/resourcemanager.projectIamAdmin — cover SA *creation*
# and *project*-level IAM, but NOT *service-account-resource*-level setIamPolicy, which only
# roles/iam.serviceAccountAdmin grants. Managed here (additive; the apply SA's projectIamAdmin lets
# it set this) so SA-level IAM stays fully in Terraform rather than a manual gcloud grant.
resource "google_project_iam_member" "tf_apply_sa_admin" {
  project = var.project_id
  role    = "roles/iam.serviceAccountAdmin"
  member  = "serviceAccount:${var.name_prefix}-sa-tf-apply@${var.project_id}.iam.gserviceaccount.com"
}

# ── KMS ───────────────────────────────────────────────────────────────────────
#
# Plain resources — created normally in every environment. NOTE: GCP soft-deletes a
# KMS KeyRing/CryptoKey and reserves the name for 30 days, so if you ever DESTROY and
# re-apply within that window the create will 409 ("already exists"). That is a rare,
# one-off event — recover with a single manual import, NOT a permanent `import` block
# (which otherwise breaks every brand-new environment's first apply):
#   terragrunt import google_kms_key_ring.main \
#     "projects/<project>/locations/<region>/keyRings/<prefix>-kms-kr"
#   terragrunt import google_kms_crypto_key.trust_dek \
#     "projects/<project>/locations/<region>/keyRings/<prefix>-kms-kr/cryptoKeys/<prefix>-kms-trust-dek"

resource "google_kms_key_ring" "main" {
  name     = "${var.name_prefix}-kms-kr"
  location = var.region
  project  = var.project_id
}

resource "google_kms_crypto_key" "trust_dek" {
  name            = "${var.name_prefix}-kms-trust-dek"
  key_ring        = google_kms_key_ring.main.id
  rotation_period = "7776000s" # 90 days

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "SOFTWARE" # upgrade to HSM in prod
  }

  lifecycle {
    prevent_destroy = false
  }
}

# sa-api can wrap/unwrap DEKs via this key (trust-plan encryption)
resource "google_kms_crypto_key_iam_member" "api_kms" {
  crypto_key_id = google_kms_crypto_key.trust_dek.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_service_account.sa_api.email}"
}

# ── KMS MAC key — seals pdf_sign_events HMACs via KMS MacSign/MacVerify ───────
# Separate MAC-purpose key (the trust_dek above is ENCRYPT_DECRYPT and cannot MAC). The HMAC
# key never leaves KMS, so an app/DB compromise can't forge a signing-event seal.
# Single non-rotating version (rotation would need per-row version tracking — see backend
# signingEventService.js). If this key is ever destroyed + re-applied within KMS's 30-day name
# reservation, add an `import` block like trust_dek above.
resource "google_kms_crypto_key" "sign_hmac" {
  name     = "${var.name_prefix}-kms-sign-hmac"
  key_ring = google_kms_key_ring.main.id
  purpose  = "MAC"

  version_template {
    algorithm        = "HMAC_SHA256"
    protection_level = "SOFTWARE" # upgrade to HSM in prod
  }

  lifecycle {
    prevent_destroy = false
  }
}

# sa-api can MacSign/MacVerify with this key
resource "google_kms_crypto_key_iam_member" "api_sign_hmac" {
  crypto_key_id = google_kms_crypto_key.sign_hmac.id
  role          = "roles/cloudkms.signerVerifier"
  member        = "serviceAccount:${google_service_account.sa_api.email}"
}

# ── Secret Manager — skeleton secrets (values populated after apply) ──────────

locals {
  # Dev-only Platform CA secret CONTAINERS (opt-in). Values are populated out-of-band via the
  # secret-population runbook — NEVER a Terraform secret-version, so no PEM ever enters TF state.
  ca_secret_ids = var.enable_local_platform_ca_secrets ? ["platform-ca-cert-pem", "platform-ca-key-pem"] : []

  secret_ids = toset(concat([
    # Main backend secrets
    "db-host",
    "db-port",
    "db-name",
    "db-user",
    "db-password",
    "firebase-storage-bucket",
    "firebase-admin-sdk-json",
    "cors-origin",
    "admin-email",
    # server-kek-master-key REMOVED (G5, 2026-07-15): trust-plan KEK root + signing seals are
    # Cloud KMS-only; no app/scanner env references it (engine #44 + infra #29). Destroying the
    # secret container + versions here is the final teardown of the retired master key.
    # Guest-sharing (Drop-Zone + Secure Outbound Share): HS256 secret that signs guest-session
    # JWTs. Shared by both features; value populated out-of-band (>=32 chars random), never a
    # TF secret-version. See plans/gusturl-infra-plan.md.
    "drop-zone-jwt-secret",
    # Platform-api secrets
    "platform-db-user", # read-only postgres user for platform-api
    "platform-db-password",
    "platform-private-ip",   # PRIVATE_BIND_IP: Tailscale/WireGuard/VPC IP — set at deploy time
    "platform-cors-origins", # space-separated origin list for platform-api CORS
    "firebase-project-id",   # shared with platform-api
  ], local.ca_secret_ids))
}

resource "google_secret_manager_secret" "secrets" {
  for_each  = local.secret_ids
  secret_id = "${var.name_prefix}-${each.key}"
  project   = var.project_id

  replication {
    auto {}
  }

  labels = {
    env    = split("-", var.name_prefix)[2] # extracts "sandbox" from "swpt-mw1-sandbox"
    tenant = split("-", var.name_prefix)[0]
  }
}
