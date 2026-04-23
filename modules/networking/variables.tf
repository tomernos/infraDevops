variable "project_id" { type = string }
variable "region"     { type = string }

variable "vpc_name" {
  type        = string
  description = "e.g. swpt-mw1-sandbox-vpc"
}

variable "subnet_cidr" {
  type    = string
  default = "10.10.0.0/20"
}

variable "pods_cidr" {
  type        = string
  default     = "10.20.0.0/16"
  description = "Secondary range reserved for future GKE pods"
}

variable "services_cidr" {
  type        = string
  default     = "10.30.0.0/20"
  description = "Secondary range reserved for future GKE services"
}

variable "enable_nat" {
  type    = bool
  default = true
}
