output "instance_name"    { value = google_sql_database_instance.main.name }
output "private_ip"       { value = google_sql_database_instance.main.private_ip_address }
output "connection_name"  { value = google_sql_database_instance.main.connection_name }
output "db_name"          { value = google_sql_database.app_db.name }
output "db_user"          { value = google_sql_user.app_user.name }

output "db_password" {
  value       = random_password.db_password.result
  sensitive   = true
  description = "After apply: run scripts/populate-secrets.sh to push this into Secret Manager"
}
