variable "project_id" { type = string }
variable "region" { type = string }
variable "name_prefix" { type = string }

variable "sa_api_email" {
  type        = string
  default     = ""
  description = <<-EOT
    BARE email of the runtime API service account, granted repo-scoped reader. Optional: leave empty
    in a compute-only project that runs no API service (the central CI runner project) — Cloud Run
    there pulls in-project images via its own service agent, so no explicit grant is needed.
  EOT
}

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

variable "extra_writer_sa_emails" {
  type        = list(string)
  default     = []
  description = <<-EOT
    Extra service-account emails (BARE, no "serviceAccount:" prefix) granted repo-scoped
    roles/artifactregistry.writer on THIS registry. Use for cross-project PUSH — e.g.
    build-runner-image.yml authenticates via DEV WIF as the dev engine deploy SA but publishes the
    runner image into the central shared registry. Same applied-with-this-env's-credentials rule as
    extra_reader_sa_emails. Default empty → no behavior change for envs that omit it.
  EOT
}
