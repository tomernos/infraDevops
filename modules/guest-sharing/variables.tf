variable "project_id" { type = string }
variable "region" { type = string }
variable "name_prefix" { type = string }

variable "sa_api_email" {
  type        = string
  description = "Runtime API service account (from the security unit). Also runs the scanner service; granted quarantine objectAdmin + token-creator-on-self here."
}

variable "vpc_network" {
  type        = string
  description = "VPC network resource path (projects/*/global/networks/*) for the scanner's Direct VPC Egress."
}

variable "subnetwork" {
  type        = string
  description = "Subnet resource path (projects/*/regions/*/subnetworks/*) for the scanner's Direct VPC Egress."
}

variable "api_service_name" {
  type        = string
  description = "Engine API Cloud Run service name — Cloud Scheduler's cleanup target gets run.invoker on it."
}

variable "api_service_uri" {
  type        = string
  description = "Engine API base URL (https://...run.app) — Cloud Scheduler POSTs {uri}/internal/run-cleanup."
}

variable "image_url" {
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello:latest"
  description = "Initial scanner app image — CI overwrites on deploy (ignored in TF state). Same backend image as the API."
}

variable "clamav_image" {
  type        = string
  default     = "clamav/clamav:latest"
  description = "clamd sidecar image. Pin to a digest for reproducible signature DB baselines."
}

variable "scanner_max_instances" {
  type        = number
  default     = 2
  description = "Max scanner instances; scales to zero when idle."
}

variable "cleanup_schedule" {
  type        = string
  default     = "0 * * * *"
  description = "Cron for the retention/cleanup job (default hourly)."
}
