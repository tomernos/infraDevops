variable "project_id" { type = string }
variable "region" { type = string }
variable "name_prefix" { type = string }
variable "sa_api_email" { type = string }

variable "extra_reader_sa_emails" {
  type        = list(string)
  default     = []
  description = <<-EOT
    Extra service-account emails (BARE, no "serviceAccount:" prefix) granted repo-scoped
    roles/artifactregistry.reader on THIS registry, in addition to sa_api. Use for cross-project
    pull — e.g. the PROD engine deploy SA that promotes/pulls images built in the dev (shared build)
    registry. The binding is applied with THIS env's credentials (the member is just a principal
    string, so no dependency on the other project's state), and the applying SA must own IAM on this
    registry (the env's tf-apply SA does). Default empty → no behavior change for envs that omit it.
  EOT
}
