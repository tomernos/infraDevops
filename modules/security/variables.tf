variable "project_id" { type = string }
variable "region" { type = string }

variable "name_prefix" {
  type        = string
  description = "Prefix for all resource names, e.g. swpt-mw1-sandbox"
}

variable "enable_local_platform_ca_secrets" {
  type        = bool
  default     = false
  description = "Create dev-only local Platform CA secret CONTAINERS (cert + key). Containers only — versions are populated out-of-band via the runbook, never as a Terraform secret-version (no PEM in state)."
}

variable "enable_data_access_audit_logs" {
  type        = bool
  default     = false
  description = "Enable Cloud Audit Data Access logs for cloudkms.googleapis.com (DATA_READ + DATA_WRITE) and secretmanager.googleapis.com (DATA_READ) on the project — per-decrypt/per-MAC/per-secret-access trail (NOW-3 / gap G-03). Opt-in per env; costs log volume. See audit.tf."
}

# ⚠️ ROTATION-SAFETY GATE — read before flipping true in ANY existing env.
# When true, Terraform GENERATES the drop-zone-jwt-secret value (random_password) and writes it as
# the FIRST secret-version, so a brand-new environment self-seeds instead of needing the out-of-band
# secret-population runbook. Default false because every ALREADY-LIVE env (dev, prod) had this value
# hand-injected and its services mount it at `latest`; creating a TF version there would push a NEW
# version, move `latest`, and ROTATE the live signing key (guest-session JWTs break). Rules:
#   • Fresh env with NO existing version  → set true on the first apply (TF seeds version 1).
#   • Any env already seeded out-of-band  → LEAVE false (TF never touches the live `latest`).
#   • Once true in a fresh env, KEEP it true — flipping back to false destroys the TF-owned version.
# The generated version also carries lifecycle.ignore_changes=[secret_data] (see main.tf) so even
# when enabled TF never re-writes/rotates the value on later applies. To have prod ADOPT its existing
# hand-injected version instead of leaving it unmanaged, `terraform import` it — see main.tf note.
variable "seed_drop_zone_jwt_secret" {
  type        = bool
  default     = false
  description = "Generate + seed the FIRST version of drop-zone-jwt-secret from Terraform (random_password). Default false. Set true ONLY on a fresh env with no hand-injected version — see the rotation-safety note above; enabling it in a live env would rotate the signing key."
}

# NOTE: the quarantine bucket + its CORS moved to modules/guest-sharing (sole owner) — see
# storage.tf. The `enable_quarantine_bucket` / `quarantine_cors_origins` vars were removed with it.
