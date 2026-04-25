output "uptime_check_id" {
  value = google_monitoring_uptime_check_config.api_health.uptime_check_id
}

output "notification_channel_ids" {
  value = local.channel_ids
}
