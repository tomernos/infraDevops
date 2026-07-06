output "platform_api_url" {
  value       = module.api.uri
  description = "Public HTTPS URL of platform-api. Bake into the panel image as VITE_PLATFORM_API_URL."
}

output "platform_panel_url" {
  value       = module.panel.uri
  description = "Public HTTPS URL of the admin panel. Add to Firebase authorized domains."
}

output "platform_sa_email" {
  value       = google_service_account.platform.email
  description = "Shared runtime service account for both platform services."
}
