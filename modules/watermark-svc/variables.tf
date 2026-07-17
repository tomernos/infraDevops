variable "project_id" { type = string }
variable "region" { type = string }
variable "name_prefix" { type = string }

variable "invoker_sa_email" {
  type        = string
  description = "Service account allowed to invoke the watermark service (the API runtime SA). No other principal — never allUsers."
}

variable "max_instances" {
  type        = number
  default     = 2
  description = "Maximum Cloud Run instances; scales to zero when idle"
}

variable "mount_shared_secret" {
  type        = bool
  default     = false
  description = "Mount WATERMARK_SHARED_SECRET into the service. Keep false until the secret container HAS a version — a secret_key_ref:latest against a version-less secret fails revision creation. Flip true (same PR as the real image + API wiring) once the value is injected out-of-band."
}

variable "image_url" {
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello:latest"
  description = "Initial image — CI overwrites this on every deploy (ignored in TF state). NOTE: nothing builds watermark-svc yet (ci-watermark.yml is a PR gate only), so this default is what actually runs until a deploy pipeline exists — never wire WATERMARK_SVC_URL into the API while it does."
}
