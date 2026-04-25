variable "project_id"  { type = string }
variable "name_prefix" { type = string }

variable "dns_zone_name" {
  type        = string
  description = "Cloud DNS managed zone name (e.g. sweptlock-com)"
}

variable "dns_name" {
  type        = string
  description = "Domain with trailing dot (e.g. sweptlock.com.)"
}

variable "vm_ip" {
  type        = string
  description = "Static external IP of the VM — used for A records"
}

variable "subdomain" {
  type        = string
  description = "Subdomain for this env (e.g. sandbox, api-sandbox, empty string for apex)"
  default     = ""
}

variable "ttl" {
  type    = number
  default = 300
}
