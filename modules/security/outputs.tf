output "sa_api_email"      { value = google_service_account.sa_api.email }
output "sa_migrator_email" { value = google_service_account.sa_migrator.email }
output "kms_key_ring_id"   { value = google_kms_key_ring.main.id }
output "kms_trust_dek_id"  { value = google_kms_crypto_key.trust_dek.id }

output "secret_names" {
  value       = { for k, v in google_secret_manager_secret.secrets : k => v.name }
  description = "Full Secret Manager resource names, used to populate versions after apply"
}
