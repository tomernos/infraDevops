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

variable "enable_quarantine_bucket" {
  type        = bool
  default     = false
  description = "Manage the drop-zone quarantine bucket (guest signed-URL uploads). Enable only in envs that run the engine; leaves other envs untouched. The bucket pre-existed Terraform, so the first apply in an enabled env IMPORTS it (see the import block in storage.tf)."
}

variable "quarantine_cors_origins" {
  type        = list(string)
  default     = []
  description = "First-party web origins allowed to PUT to the quarantine bucket via V4 signed URLs (browser → GCS directly). MUST stay in lockstep with the API CORS_ORIGIN allowlist — a drift here silently breaks drop-zone uploads from the missing origin. Empty list = no CORS block."
}
