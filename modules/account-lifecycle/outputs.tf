output "deletion_sweeper_sa_email" {
  value       = google_service_account.sa_deletion_sweeper.email
  description = "Cloud Scheduler SA. The API's /internal/run-deletion-sweep accepts only this OIDC identity (DELETION_SWEEPER_SA)."
}

output "deletion_sweep_job_name" {
  value       = google_cloud_scheduler_job.deletion_sweep.name
  description = "Scheduler job name, for a manual `gcloud scheduler jobs run` smoke test."
}
