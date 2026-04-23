variable "project_id"       { type = string }
variable "region"           { type = string }
variable "name_prefix"      { type = string }
variable "subnet_self_link" { type = string }
variable "vpc_name"         { type = string }
variable "sa_api_email"     { type = string }

variable "machine_type" {
  type    = string
  default = "e2-standard-2"
}

variable "image_url" {
  type        = string
  description = "Full Artifact Registry image URL including tag"
}
