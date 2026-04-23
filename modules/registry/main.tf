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
