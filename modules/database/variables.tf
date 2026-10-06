variable "project_id"    { type = string }
variable "region"        { type = string }
variable "instance_name" { type = string }
variable "vpc_self_link" { type = string }

variable "db_name" {
  type    = string
  default = "aladin_db"
}

variable "db_user" {
  type    = string
  default = "sweptlock"
}

variable "tier" {
  type    = string
  default = "db-g1-small"
}

variable "disk_size_gb" {
  type    = number
  default = 20
}

variable "ha_enabled" {
  type    = bool
  default = false
}

variable "pitr_enabled" {
  type    = bool
  default = false
}

variable "backup_retention_days" {
  type    = number
  default = 7
}

variable "deletion_protection" {
  type    = bool
  default = true
  description = "Set false in sandbox to allow terraform destroy"
}
