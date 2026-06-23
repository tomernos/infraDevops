variable "project_id" { type = string }
variable "region" { type = string }

variable "name_prefix" {
  type        = string
  description = "Prefix for all resource names, e.g. swpt-mw1-dev"
}

variable "runner_image_name" {
  type        = string
  default     = "runner:latest"
  description = "Image name:tag inside the env's Artifact Registry repo (<name_prefix>-registry)"
}
