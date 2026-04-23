output "repository_id" { value = google_artifact_registry_repository.sweptlock.repository_id }

output "image_base_url" {
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.sweptlock.repository_id}"
  description = "Base URL for pushing/pulling images. Append /<image>:<tag>"
}
