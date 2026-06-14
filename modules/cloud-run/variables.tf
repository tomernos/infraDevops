variable "project_id" { type = string }
variable "region" { type = string }
variable "name_prefix" { type = string }

variable "sa_api_email" {
  type        = string
  description = "Service account the Cloud Run container runs as"
}

variable "sa_ci_deploy_email" {
  type        = string
  description = "CI service account that deploys new revisions — granted roles/run.developer"
}

variable "vpc_self_link" {
  type        = string
  description = "VPC network self_link for Direct VPC Egress"
}

variable "subnet_self_link" {
  type        = string
  description = "Subnet self_link for Direct VPC Egress (Cloud Run gets IPs from this range)"
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
