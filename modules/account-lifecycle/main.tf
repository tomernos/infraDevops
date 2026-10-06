# Account lifecycle: the Cloud Scheduler trigger for the Right-to-be-Forgotten grace-period
# erasure sweep (engine POST /internal/run-deletion-sweep).
#
# The engine deliberately does NOT run this sweep on an in-process timer: Cloud Run scales to
# zero (a timer stops when the instance is idle-killed) and runs several instances (a timer would
# fire once per instance). An external, single cadence is the intended shape. Without this job,
# a user who requests deletion waits out the grace period and is then never erased.
#
# Separate from modules/guest-sharing on purpose: that module is the Drop-Zone feature, this is
# account erasure. The two scheduler identities are also separate, so the engine's OIDC guards
# (CLEANUP_SCHEDULER_SA vs DELETION_SWEEPER_SA) each admit exactly one caller and the audit log
# names which job triggered an erasure.
#
# Assumes the cloudscheduler API is already enabled (scripts/bootstrap.sh; guest-sharing relies on
# it too).

resource "google_service_account" "sa_deletion_sweeper" {
  account_id   = "${var.name_prefix}-sa-del-sweep"
  display_name = "Sweptlock account-deletion sweeper (Cloud Scheduler)"
  description  = "OIDC identity Cloud Scheduler uses to call the engine API /internal/run-deletion-sweep. Holds run.invoker on the API only."
  project      = var.project_id
}

resource "google_cloud_run_v2_service_iam_member" "sweeper_invoke_api" {
  project  = var.project_id
  location = var.region
  name     = var.api_service_name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.sa_deletion_sweeper.email}"
}

resource "google_cloud_scheduler_job" "deletion_sweep" {
  name        = "${var.name_prefix}-deletion-sweep"
  description = "RTBF: erase accounts whose deletion grace period has elapsed."
  project     = var.project_id
  region      = var.region
  schedule    = var.deletion_sweep_schedule
  time_zone   = "Etc/UTC"

  # A run claims at most a fixed batch (FOR UPDATE SKIP LOCKED) and returns 500 on failure.
  # Retries are safe: claimed-but-failed rows are recorded 'failed', never re-erased blindly.
  retry_config {
    retry_count          = 3
    min_backoff_duration = "60s"
    max_backoff_duration = "600s"
  }

  http_target {
    uri         = "${var.api_service_uri}/internal/run-deletion-sweep"
    http_method = "POST"
    oidc_token {
      service_account_email = google_service_account.sa_deletion_sweeper.email
      audience              = var.api_service_uri
    }
  }

  depends_on = [google_cloud_run_v2_service_iam_member.sweeper_invoke_api]
}
