variable "project_id" { type = string }

variable "name_prefix" {
  type        = string
  description = "Resource-name prefix, e.g. swpt-mw1-dev"
}

variable "component" {
  type        = string
  description = "Short component slug baked into the SA id: {name_prefix}-sa-{component}-deploy (e.g. eng, plat)."

  validation {
    # GCP account_id is [a-z][a-z0-9-]{4,28}[a-z0-9], max 30 chars. Keep the slug short and lowercase.
    condition     = can(regex("^[a-z][a-z0-9]{1,4}$", var.component))
    error_message = "component must be 2-5 lowercase alphanumerics (e.g. eng, plat)."
  }
}

variable "display_name" {
  type        = string
  description = "Human-readable SA display name."
}

variable "description" {
  type        = string
  description = "SA description."
}

variable "project_roles" {
  type        = list(string)
  description = "Project-level IAM roles bound to this deploy SA (least privilege for the workflow)."
}

variable "act_as_service_accounts" {
  type        = list(string)
  default     = []
  description = <<-EOT
    Emails of the RUNTIME service accounts this deploy SA must impersonate (roles/iam.serviceAccountUser)
    to deploy Cloud Run revisions that run as them. Usually one (the service's runtime SA).
  EOT
}

variable "wif_pool_id" {
  type        = string
  default     = ""
  description = <<-EOT
    Short id of the WIF pool this SA federates against. Defaults to "<name_prefix>-wif-pool" (the
    bootstrap convention); override only if a non-standard pool is used. The module derives the full
    resource name from the project number internally.
  EOT
}

variable "github_repo" {
  type        = string
  description = <<-EOT
    The GitHub "owner/repo" allowed to impersonate this SA, matched EXACTLY against the OIDC
    attribute.repository claim (case-sensitive). A casing mismatch fails auth silently.
  EOT

  validation {
    condition     = can(regex("^[^/]+/[^/]+$", var.github_repo))
    error_message = "github_repo must be in owner/repo form (exactly one slash)."
  }
}
