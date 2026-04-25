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

# ── KMS ───────────────────────────────────────────────────────────────────────
#
# GCP KMS KeyRings cannot be truly deleted — GCP soft-deletes them and reserves
# the name for 30 days. Any apply within that window will 409 without an import.
#
# These import blocks are idempotent:
#   - Resource already in state  → no-op (normal path)
#   - Resource in GCP, not state → imports it automatically (destroy/re-apply path)
#   - Brand-new environment      → comment both import blocks out for the first
#                                  apply only; uncomment after.

import {
  id = "projects/${var.project_id}/locations/${var.region}/keyRings/${var.name_prefix}-kms-kr"
  to = google_kms_key_ring.main
}

resource "google_kms_key_ring" "main" {
  name     = "${var.name_prefix}-kms-kr"
  location = var.region
  project  = var.project_id
}

import {
  id = "projects/${var.project_id}/locations/${var.region}/keyRings/${var.name_prefix}-kms-kr/cryptoKeys/${var.name_prefix}-kms-trust-dek"
  to = google_kms_crypto_key.trust_dek
}

resource "google_kms_crypto_key" "trust_dek" {
  name            = "${var.name_prefix}-kms-trust-dek"
  key_ring        = google_kms_key_ring.main.id
  rotation_period = "7776000s"  # 90 days

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "SOFTWARE"  # upgrade to HSM in prod
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

# ── Secret Manager — skeleton secrets (values populated after apply) ──────────

locals {
  secret_ids = toset([
    "db-host",
    "db-port",
    "db-name",
    "db-user",
    "db-password",
    "firebase-storage-bucket",
    "firebase-admin-sdk-json",
    "cors-origin",
    "admin-email",
    "server-kek-master-key",   # Phase 1: still env-var based; Phase 2: replaced by Cloud KMS
  ])
}

resource "google_secret_manager_secret" "secrets" {
  for_each  = local.secret_ids
  secret_id = "${var.name_prefix}-${each.key}"
  project   = var.project_id

  replication {
    auto {}
  }

  labels = {
    env    = split("-", var.name_prefix)[2]  # extracts "sandbox" from "swpt-mw1-sandbox"
    tenant = split("-", var.name_prefix)[0]
  }
}
