output "quarantine_bucket" {
  value       = google_storage_bucket.quarantine.name
  description = "Quarantine bucket name (also QUARANTINE_BUCKET on the API/scanner)."
}

output "scanner_service_name" {
  value       = google_cloud_run_v2_service.scanner.name
  description = "Malware-scanner Cloud Run service name (CI updates its app image)."
}

output "scan_events_sa_email" {
  value       = google_service_account.sa_eventarc_scan.email
  description = "Eventarc trigger SA — the scanner's /internal/scan-events accepts only this OIDC identity."
}

output "cleanup_sa_email" {
  value       = google_service_account.sa_cleanup.email
  description = "Cloud Scheduler SA — the API's /internal/run-cleanup accepts only this OIDC identity (CLEANUP_SCHEDULER_SA)."
}
