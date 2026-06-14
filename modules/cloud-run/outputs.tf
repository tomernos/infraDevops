output "service_url" {
  value       = google_cloud_run_v2_service.api.uri
  description = "Public HTTPS URL of the Cloud Run API — use as EXPO_PUBLIC_API_BASE_URL"
}

output "service_name" {
  value       = google_cloud_run_v2_service.api.name
  description = "Cloud Run service name — used in gcloud run deploy"
}
