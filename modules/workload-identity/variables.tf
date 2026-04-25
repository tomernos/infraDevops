variable "project_id"   { type = string }
variable "region"       { type = string }
variable "name_prefix"  { type = string }

variable "github_owner" {
  type        = string
  description = "GitHub user or org owning both repos (e.g. tomernos)"
}

variable "app_repo" {
  type        = string
  description = "App repository name (e.g. Aladin)"
}

variable "infra_repo" {
  type        = string
  description = "Infra repository name (e.g. sweptlock-infra)"
}

variable "state_bucket" {
  type        = string
  description = "GCS bucket holding Terraform state — ci-plan SA gets read access"
}

variable "sa_api_email" {
  type        = string
  description = "Email of sa-api — ci-deploy needs serviceAccountUser on it for osLogin"
}
