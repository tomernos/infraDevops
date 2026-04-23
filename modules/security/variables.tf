variable "project_id"  { type = string }
variable "region"      { type = string }

variable "name_prefix" {
  type        = string
  description = "Prefix for all resource names, e.g. swpt-mw1-sandbox"
}
