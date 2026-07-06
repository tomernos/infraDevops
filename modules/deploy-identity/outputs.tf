output "sa_email" {
  description = "Deploy SA email — paste into the repo's GitHub deploy workflow as its service_account secret."
  value       = google_service_account.this.email
}

output "sa_account_id" {
  description = "Deploy SA account id (the {name_prefix}-sa-{component}-deploy short name)."
  value       = google_service_account.this.account_id
}
