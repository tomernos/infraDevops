resource "google_artifact_registry_repository" "sweptlock" {
  repository_id = "${var.name_prefix}-registry"
  location      = var.region
  format        = "DOCKER"
  description   = "Sweptlock Docker images"
  project       = var.project_id
}

# Allow sa-api to pull images from this registry. Optional: a compute-only project (the central CI
# runner project) runs no API service, and Cloud Run there pulls the runner image via the project's
# own Cloud Run service agent, which reads in-project registries by default.
resource "google_artifact_registry_repository_iam_member" "api_reader" {
  count      = var.sa_api_email == "" ? 0 : 1
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.sweptlock.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${var.sa_api_email}"
}

# sa_api_email became optional, which put api_reader behind count. Keeps the existing dev/prod state
# addresses stable — without this the live binding would plan as destroy+create.
moved {
  from = google_artifact_registry_repository_iam_member.api_reader
  to   = google_artifact_registry_repository_iam_member.api_reader[0]
}

# Cross-project pull: additional deploy SAs (e.g. the PROD engine deploy SA promoting/pulling images
# built in the dev shared-build registry) get repo-scoped reader here. Same binding shape as
# api_reader above; member is just a principal string so no cross-project state dependency is needed.
resource "google_artifact_registry_repository_iam_member" "extra_readers" {
  for_each   = toset(var.extra_reader_sa_emails)
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.sweptlock.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${each.value}"
}

# Cross-project PUSH: a CI workflow that authenticates via one env's WIF but publishes an image into
# THIS registry (e.g. build-runner-image.yml authenticates as the dev engine deploy SA and pushes the
# runner image into the central shared registry). Repo-scoped writer, not a project-level role.
resource "google_artifact_registry_repository_iam_member" "extra_writers" {
  for_each   = toset(var.extra_writer_sa_emails)
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.sweptlock.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${each.value}"
}
