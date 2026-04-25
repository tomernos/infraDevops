output "name_servers" {
  description = "NS records to set at your registrar to delegate to Cloud DNS"
  value       = google_dns_managed_zone.main.name_servers
}

output "zone_name" {
  value = google_dns_managed_zone.main.name
}

output "app_fqdn" {
  description = "The fully-qualified domain name the app is reachable at"
  value       = trimsuffix(local.fqdn, ".")
}
