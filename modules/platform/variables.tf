variable "project_id" { type = string }
variable "region" { type = string }
variable "name_prefix" { type = string }

variable "vpc_network" {
  type        = string
  description = "VPC network resource path (projects/*/global/networks/*) for Direct VPC Egress."
}

variable "subnetwork" {
  type        = string
  description = "Subnet resource path (projects/*/regions/*/subnetworks/*) for Direct VPC Egress."
}

variable "max_instances" {
  type        = number
  default     = 3
  description = "Maximum Cloud Run instances per service; both scale to zero when idle."
}

variable "firebase_project_id" {
  type        = string
  description = "Firebase project id for Admin token verification (FIREBASE_PROJECT_ID)."
}

variable "api_image" {
  type        = string
  description = "platform-api container image (Artifact Registry). Built from sweptlock-platform/api."
}

variable "panel_image" {
  type        = string
  description = <<-EOT
    platform-panel container image. Built from sweptlock-platform/panel with the platform-api URL
    baked in via VITE_PLATFORM_API_URL. Deploy the API first, then build the panel image against
    its URL. Defaults to the Cloud Run hello image for the initial (pre-panel-build) apply.
  EOT
  default     = "us-docker.pkg.dev/cloudrun/container/hello:latest"
}

variable "engine_api_base_url" {
  type        = string
  default     = ""
  description = "Engine API base URL for platform-api's engineClient (ENGINE_API_BASE_URL). Empty = not injected (the app falls back to localhost:4000, which fails on Cloud Run)."

  validation {
    condition     = var.engine_api_base_url == "" || can(regex("^https://", var.engine_api_base_url))
    error_message = "engine_api_base_url must be an https URL."
  }
}
