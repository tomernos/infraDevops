output "sa_runner_email" {
  value       = google_service_account.sa_runner.email
  description = "Runtime identity the runner job executes as"
}

output "job_name" {
  value       = google_cloud_run_v2_job.runner.name
  description = "Cloud Run Job name — referenced by build-android.yml (RUNNER_JOB)"
}

output "runner_image" {
  value       = local.runner_image
  description = "Full Artifact Registry image URL the job runs"
}

output "executor_sa_email" {
  value       = local.executor_sa_email
  description = "SA granted actAs on sa-runner — i.e. the identity allowed to execute the Job"
}
