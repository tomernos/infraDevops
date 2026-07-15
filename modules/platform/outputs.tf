output "platform_api_url" {
  value       = module.api.uri
  description = "Public HTTPS URL of platform-api. Bake into the panel image as VITE_PLATFORM_API_URL."
}

output "platform_panel_url" {
  value       = module.panel.uri
  description = "Public HTTPS URL of the admin panel. Add to Firebase authorized domains."
}

output "platform_sa_email" {
  value       = google_service_account.api.email
  description = "platform-api runtime service account (DB secrets + Firebase admin)."
}

output "platform_panel_sa_email" {
  value       = google_service_account.panel.email
  description = "platform-panel runtime service account (zero permissions). The deploy SA needs actAs on this to deploy the panel."
}
