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

# NOTE: the quarantine bucket + its CORS moved to modules/guest-sharing (sole owner) — see
# storage.tf. The `enable_quarantine_bucket` / `quarantine_cors_origins` vars were removed with it.
