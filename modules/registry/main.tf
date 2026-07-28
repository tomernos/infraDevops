resource "google_artifact_registry_repository" "sweptlock" {
  repository_id = "${var.name_prefix}-registry"
  location      = var.region
  format        = "DOCKER"
  description   = "Sweptlock Docker images"
  project       = var.project_id
}

# Allow sa-api to pull images from this registry
resource "google_artifact_registry_repository_iam_member" "api_reader" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.sweptlock.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${var.sa_api_email}"
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
