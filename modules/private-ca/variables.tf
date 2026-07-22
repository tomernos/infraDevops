# Platform CA (Google Certificate Authority Service) — the production issuer of end-entity
# PDF-signing certificates. Private keys live in a Google-managed HSM (non-extractable); the
# engine only submits a public key and receives a signed cert. See
# regions/me-west1/prod/prod-ca-architecture.md.
#
# project_id and region are injected by root.hcl (env.hcl/region.hcl locals merged into inputs).

variable "project_id" { type = string }
variable "region" { type = string }

variable "name_prefix" {
  type        = string
  description = "Resource name prefix, e.g. swpt-mw1-prod."
}

variable "ca_pool_tier" {
  type        = string
  default     = "ENTERPRISE"
  description = "CA pool tier. ENTERPRISE tracks issued certificates so they can be revoked (required by the app's revokeCertificate path); DEVOPS does not."
  validation {
    condition     = contains(["ENTERPRISE", "DEVOPS"], var.ca_pool_tier)
    error_message = "ca_pool_tier must be ENTERPRISE or DEVOPS."
  }
}

variable "root_ca_organization" {
  type        = string
  default     = "SweptLock"
  description = "Organization in the root CA subject."
}

variable "root_ca_common_name" {
  type        = string
  default     = "SweptLock Platform Root CA"
  description = "Common name of the root CA."
}

variable "root_ca_key_algorithm" {
  type        = string
  default     = "RSA_PKCS1_4096_SHA256"
  description = "HSM key algorithm for the root CA."
}

variable "root_ca_lifetime" {
  type        = string
  default     = "315360000s" # 10 years
  description = "Root CA lifetime as a seconds-duration string."
}

variable "certificate_requester_members" {
  type        = list(string)
  default     = []
  description = "IAM members (e.g. serviceAccount:sa-api@...) granted roles/privateca.certificateRequester on the pool — least privilege: they may request certs, NOT administer the CA."
}

variable "deletion_protection" {
  type        = bool
  default     = true
  description = "Protect the root CA from accidental destroy (prod default true)."
}
