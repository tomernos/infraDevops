output "uri" {
  value       = google_cloud_run_v2_service.watermark.uri
  description = "Internal HTTPS URL of the watermark service — inject into the API as WATERMARK_SVC_URL"
}

output "sa_email" {
  value       = google_service_account.sa_watermark.email
  description = "Watermark service runtime SA email"
}
