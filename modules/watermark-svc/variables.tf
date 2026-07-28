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

# ⚠️ ROTATION-SAFETY GATE — read before flipping true in ANY existing env.
# When true, Terraform GENERATES the watermark X-WM-Auth shared secret (random_password) and writes
# it as the FIRST secret-version, so a fresh env self-seeds instead of running the out-of-band
# injection step (after which mount_shared_secret can go true in the same apply). Default false
# because every ALREADY-LIVE env had this value hand-injected and the service mounts it at `latest`;
# a TF version there would push a NEW version, move `latest`, and ROTATE the live shared secret,
# breaking API↔service auth until both sides re-sync. Rules:
#   • Fresh env with NO existing version  → set true on the first apply (TF seeds version 1).
#   • Any env already seeded out-of-band  → LEAVE false (TF never touches the live `latest`).
#   • Once true in a fresh env, KEEP it true — flipping back to false destroys the TF-owned version.
# The generated version also carries lifecycle.ignore_changes=[secret_data] (see main.tf) so even
# when enabled TF never re-writes/rotates the value on later applies.
variable "seed_shared_secret" {
  type        = bool
  default     = false
  description = "Generate + seed the FIRST version of the watermark shared secret from Terraform (random_password). Default false. Set true ONLY on a fresh env with no hand-injected version — see the rotation-safety note above; enabling it in a live env would rotate the shared secret. Independent of mount_shared_secret (which controls whether the service mounts it)."
}

variable "image_url" {
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello:latest"
  description = "Initial image — CI overwrites this on every deploy (ignored in TF state). NOTE: nothing builds watermark-svc yet (ci-watermark.yml is a PR gate only), so this default is what actually runs until a deploy pipeline exists — never wire WATERMARK_SVC_URL into the API while it does."
}
