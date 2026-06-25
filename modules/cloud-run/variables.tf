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
  description = "Cloud KMS crypto-key resource name for trust-plan KEK wrapping (gcp_kms provider). Empty = backend falls back to the local SERVER_KEK_MASTER_KEY."
}
