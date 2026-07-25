# ── Data Access audit logs — KMS + Secret Manager (NOW-3 / threat-model gap G-03) ─────────────
#
# Turns on Cloud Audit "Data Access" logging for exactly the two services this module owns keys
# and secrets for. Without these, KMS Encrypt/Decrypt/MacSign/MacVerify and Secret Manager
# AccessSecretVersion calls leave NO per-call trail — any KMS/secret incident forces an
# assume-full-exposure posture. With them, blast radius is provable from Cloud Logging.
#
# Scope decisions (deliberate — Data Access logs cost money and are noisy):
#   * ONLY cloudkms + secretmanager. Do not widen to allServices.
#   * ADMIN_READ is already on org-wide by default — not duplicated here.
#   * KMS gets DATA_READ + DATA_WRITE (crypto operations: per-decrypt / per-encrypt / per-MAC).
#   * Secret Manager gets DATA_READ only (AccessSecretVersion — the payload reads we care about).
#
# Semantics: google_project_iam_audit_config is AUTHORITATIVE per (project, service) pair — keep
# each service's config defined exactly once per project, i.e. only here. The CI apply SA can set
# this: audit configs ride the project IAM policy (resourcemanager.projects.setIamPolicy), which
# roles/resourcemanager.projectIamAdmin (granted in scripts/bootstrap.sh) already covers.
#
# Follow-up (deferred, tracked in NOW-3): dedicated locked log bucket sink with retention lock.
# Today entries land in the project _Default bucket (30-day retention); the activity-log module's
# Pub/Sub pipeline is app-events only and does not carry these.

resource "google_project_iam_audit_config" "kms_data_access" {
  count   = var.enable_data_access_audit_logs ? 1 : 0
  project = var.project_id
  service = "cloudkms.googleapis.com"

  audit_log_config {
    log_type = "DATA_READ"
  }

  audit_log_config {
    log_type = "DATA_WRITE"
  }
}

resource "google_project_iam_audit_config" "secretmanager_data_access" {
  count   = var.enable_data_access_audit_logs ? 1 : 0
  project = var.project_id
  service = "secretmanager.googleapis.com"

  audit_log_config {
    log_type = "DATA_READ"
  }
}
