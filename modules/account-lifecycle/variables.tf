variable "project_id" { type = string }
variable "region" { type = string }
variable "name_prefix" { type = string }

variable "api_service_name" {
  type        = string
  description = "Engine API Cloud Run service name. The sweeper SA gets run.invoker on it."
}

variable "api_service_uri" {
  type        = string
  description = "Engine API base URL (https://...run.app). Scheduler POSTs {uri}/internal/run-deletion-sweep; also the OIDC audience."
}

variable "deletion_sweep_schedule" {
  type        = string
  default     = "17 * * * *"
  description = "Cron (UTC). Hourly by default: one run erases at most the engine's SWEEP_BATCH_SIZE (20) accounts, so a daily cadence would cap erasures at 20/day. Off the top of the hour to avoid colliding with the guest cleanup job."
}
