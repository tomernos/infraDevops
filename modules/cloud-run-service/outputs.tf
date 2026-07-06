output "uri" {
  value       = google_cloud_run_v2_service.this.uri
  description = "Public HTTPS URL of the service."
}

output "name" {
  value       = google_cloud_run_v2_service.this.name
  description = "Service name."
}
