variable "project_id" { type = string }
variable "region" { type = string }
variable "name_prefix" { type = string }

variable "sa_api_email" {
  type        = string
  description = "Service account the Cloud Run container runs as"
}

variable "vpc_network" {
  type        = string
  description = "VPC network resource path (projects/*/global/networks/*) for Direct VPC Egress. Cloud Run V2 rejects a full self_link URL here."
}

variable "subnetwork" {
  type        = string
  description = "Subnet resource path (projects/*/regions/*/subnetworks/*) for Direct VPC Egress"
}

variable "max_instances" {
  type        = number
  default     = 3
  description = "Maximum Cloud Run instances; scales to zero when idle"
}

variable "image_url" {
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello:latest"
  description = "Initial image — CI overwrites this on every deploy (ignored in TF state)"
}

variable "kek_kms_key" {
  type        = string
  default     = ""
  description = "Cloud KMS crypto-key resource name for trust-plan KEK wrapping (gcp_kms provider). KMS-only — the backend fails fast at boot if this is unset (no local master-key fallback)."
}

variable "sign_hmac_kms_key" {
  type        = string
  default     = ""
  description = "Cloud KMS CryptoKeyVersion resource name for pdf_sign_events MAC (MacSign/MacVerify). KMS-only — the backend fails fast at boot if this is unset (no local HMAC fallback)."
}

variable "watermark_svc_url" {
  type        = string
  default     = ""
  description = "Internal Cloud Run URL of the forensic watermark service. Empty = WATERMARK_SVC_URL not injected and the forensic provider stays dormant."
}

variable "watermark_shared_secret_name" {
  type        = string
  default     = ""
  description = "Secret Manager secret suffix (without name_prefix) holding the watermark X-WM-Auth shared secret. Empty = WATERMARK_SHARED_SECRET not injected."
}

# ── Platform CA (dev-only) ───────────────────────────────────────────────────
# Opt-in, inert by default. Empty ca_provider leaves all Platform CA wiring off, so the shared
# module stays safe for non-dev services. The runtime guardrails in backend caProvider.js are
# duplicated as a Cloud Run lifecycle precondition (see main.tf) — fail-closed at the deploy boundary.
variable "app_env" {
  type        = string
  default     = ""
  description = "Application deployment environment consumed by runtime security guardrails (e.g. dev). Empty leaves APP_ENV unset."
}

variable "ca_provider" {
  type        = string
  default     = ""
  description = "Platform CA provider (local | gcp_cas). Empty leaves all Platform CA wiring disabled."
}

variable "allow_local_ca" {
  type        = bool
  default     = false
  description = "Explicit dev-only opt-in for an extractable local Platform CA. Rejected unless app_env=dev and ca_provider=local."
}

variable "cas_ca_pool" {
  type        = string
  default     = ""
  description = "gcp_cas only: full CAS CA pool resource name (projects/<p>/locations/<loc>/caPools/<pool>) injected as CAS_CA_POOL. Required when ca_provider=gcp_cas."
}

variable "cas_issuing_ca" {
  type        = string
  default     = ""
  description = "gcp_cas only (optional): a specific subordinate CA id in the pool to issue from, injected as CAS_ISSUING_CA. Empty lets the pool select."
}

# ── Guest sharing (Drop-Zone + Secure Outbound Share) ────────────────────────
# Off by default so the shared module stays safe for other services. When true, the API gets the
# quarantine bucket name, the guest-session JWT secret, and the cleanup-scheduler SA (for the
# /internal/run-cleanup OIDC guard). Scanning is NOT on the API — it lives in the scanner service
# (modules/guest-sharing). See plans/gusturl-infra-plan.md.
variable "enable_guest_sharing" {
  type        = bool
  default     = false
  description = "Wire Drop-Zone / Secure-Share env + secret onto the API (dev)."
}

variable "cleanup_scheduler_sa" {
  type        = string
  default     = ""
  description = "Email of the Cloud Scheduler SA allowed to call POST /internal/run-cleanup (OIDC). Empty leaves the guard env unset."
}

# ── Account lifecycle + auth (RTBF sweeper, Auth/MFA epic, PDF Sign external signers) ────────
# All default to "" = not injected, which keeps each engine feature in its fail-closed state.
variable "deletion_sweeper_sa" {
  type        = string
  default     = ""
  description = "Email of the Cloud Scheduler SA allowed to call POST /internal/run-deletion-sweep (OIDC), from the account-lifecycle unit. Empty leaves the guard env unset (every call rejected)."
}

variable "auth_contact_cutover_date" {
  type        = string
  default     = ""
  description = "AUTH_CONTACT_CUTOVER_DATE (RFC 3339 UTC). Signups at/after it must verify a contact channel; the pending-user GC only considers rows created at/after it. Set once per env, then never change or remove: it must equal the --cutover the backfill was applied with."

  validation {
    condition     = var.auth_contact_cutover_date == "" || can(timeadd(var.auth_contact_cutover_date, "0s"))
    error_message = "auth_contact_cutover_date must be an RFC 3339 timestamp, e.g. 2026-09-25T14:38:28Z."
  }
}

variable "app_web_base_url" {
  type        = string
  default     = ""
  description = "Web app origin used in emailed MFA recovery links (APP_WEB_BASE_URL), e.g. https://<project>.web.app."

  validation {
    condition     = var.app_web_base_url == "" || can(regex("^https://[^/]+$", var.app_web_base_url))
    error_message = "app_web_base_url must be an https origin with no path or trailing slash."
  }
}

variable "sign_link_base_url" {
  type        = string
  default     = ""
  description = "Origin for PDF Sign external-signer invite links (SIGN_LINK_BASE_URL)."

  validation {
    condition     = var.sign_link_base_url == "" || can(regex("^https://", var.sign_link_base_url))
    error_message = "sign_link_base_url must be an https URL."
  }
}

variable "sign_guest_jwt_secret_name" {
  type        = string
  default     = ""
  description = "Secret suffix (secret = \"<name_prefix>-<this>\") mounted as SIGN_GUEST_JWT_SECRET. The container is created by the security module; its value is populated out-of-band. Empty = not mounted (external-signer links fail closed)."
}

variable "firebase_use_adc" {
  type        = bool
  default     = false
  description = "Keyless Firebase Admin: when true, do NOT mount FIREBASE_ADMIN_SDK_JSON (the backend falls through to ADC = the runtime SA) and grant the runtime SA the Firebase IAM roles. The org disables downloadable SA keys, so prod must run keyless; dev keeps mounting the JSON."
}
