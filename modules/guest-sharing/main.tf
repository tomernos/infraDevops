# Guest-sharing infra: Drop-Zone quarantine bucket, the malware-scanner Cloud Run service
# (backend image + clamd sidecar, Eventarc-triggered), and the Cloud Scheduler cleanup job.
# Design + DAG: ReferencesContext/sweptlock/plans/gusturl-infra-plan.md
#
# NOTE: this module assumes the eventarc / cloudscheduler / pubsub APIs are already enabled on the
# project (bootstrap concern). Enable them once if a plan errors with a disabled-service message.

# The Cloud Storage service agent is created LAZILY. Reading this data source triggers its creation
# and returns the correct email — hardcoding service-<num>@gs-project-accounts races its existence
# (400 "does not exist" on a fresh project).
data "google_storage_project_service_account" "gcs" {
  project = var.project_id
}

locals {
  # GCS service agent — Eventarc GCS triggers publish object events through it; it needs pubsub.publisher.
  gcs_service_agent = data.google_storage_project_service_account.gcs.email_address

  quarantine_bucket = "${var.name_prefix}-quarantine"

  # Web origins allowed to PUT directly to the quarantine bucket via V4 signed URLs.
  cors_origins = [
    "http://localhost:8081",
    "https://sweptlock-dev-844f2.web.app",
    "https://sweptlock.com",
  ]

  # The scanner runs the SAME backend image as the API, so it needs the same core secrets to boot
  # (DB for verdict writes, Firebase/Storage to read the quarantine object) plus the guest secret.
  scanner_secret_env = {
    DB_HOST                 = "db-host"
    DB_PORT                 = "db-port"
    DB_NAME                 = "db-name"
    DB_USER                 = "db-user"
    DB_PASSWORD             = "db-password"
    FIREBASE_ADMIN_SDK_JSON = "firebase-admin-sdk-json"
    FIREBASE_STORAGE_BUCKET = "firebase-storage-bucket"
    FIREBASE_PROJECT_ID     = "firebase-project-id"
    SERVER_KEK_MASTER_KEY   = "server-kek-master-key"
    CORS_ORIGIN             = "cors-origin"
    ADMIN_EMAIL             = "admin-email"
    DROP_ZONE_JWT_SECRET    = "drop-zone-jwt-secret"
  }
}

# ── Quarantine bucket — isolated landing zone for unauthenticated guest uploads ──
resource "google_storage_bucket" "quarantine" {
  name     = local.quarantine_bucket
  project  = var.project_id
  location = var.region

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  # Backstop: purge anything not approved/rejected in time even if the app cleanup job misses.
  # Must match backend dropZoneCleanupJob.js PENDING_MAX_DAYS (7).
  lifecycle_rule {
    action { type = "Delete" }
    condition { age = 7 }
  }

  # Guests' browsers PUT directly to the bucket via V4 signed URLs (bypasses Cloud Run's 32MB cap).
  # The signed URL binds BOTH Content-Type AND x-goog-content-length-range — the custom header
  # triggers a CORS preflight, so BOTH must be allow-listed or browser uploads silently fail.
  cors {
    origin          = local.cors_origins
    method          = ["PUT"]
    response_header = ["Content-Type", "x-goog-content-length-range"]
    max_age_seconds = 3600
  }

  labels = {
    tenant = split("-", var.name_prefix)[0]
    env    = split("-", var.name_prefix)[2]
  }
}

# The API/scanner SA reads (scan/approve), verifies generation, and deletes quarantine objects.
resource "google_storage_bucket_iam_member" "api_objectadmin" {
  bucket = google_storage_bucket.quarantine.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${var.sa_api_email}"
}

# V4 signed-URL signing on Cloud Run (workload identity, no key file) goes through the IAM signBlob
# API, which requires the SA to hold Token Creator ON ITSELF. Without this, getQuarantineUploadUrl
# 403s only in the deployed env.
resource "google_service_account_iam_member" "api_token_creator" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${var.sa_api_email}"
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${var.sa_api_email}"
}

# ── Scanner Cloud Run service — backend app + clamd sidecar (scale-to-zero) ──────
resource "google_cloud_run_v2_service" "scanner" {
  name     = "${var.name_prefix}-scanner"
  location = var.region
  project  = var.project_id

  # Dev service fully owned by Terraform — allow it to replace/destroy the scanner without a manual
  # console step (the provider defaults this to true, which blocks TF-managed teardown/replacement).
  deletion_protection = false

  # Internal only — nobody on the public internet should reach the scanner. Eventarc/Pub/Sub push is
  # Google-internal traffic. If a GCS→Pub/Sub push is ever rejected in-region, relax to
  # INGRESS_TRAFFIC_ALL (the scanner is still IAM-locked to the Eventarc SA + OIDC-checked in-app).
  ingress = "INGRESS_TRAFFIC_INTERNAL_ONLY"

  template {
    service_account = var.sa_api_email

    scaling {
      min_instance_count = 0
      max_instance_count = var.scanner_max_instances
    }

    vpc_access {
      network_interfaces {
        network    = var.vpc_network
        subnetwork = var.subnetwork
      }
      egress = "ALL_TRAFFIC" # reach Cloud SQL private IP + Google APIs via Cloud NAT
    }

    # [0] backend app (the ingress container). Talks to clamd on localhost:3310.
    containers {
      name  = "scanner-app"
      image = var.image_url

      # Do not start the app — and therefore do not let Cloud Run route the Eventarc scan request —
      # until clamd is listening on :3310. On a scale-to-zero cold start the app otherwise races
      # clamd's ~30-60s signature-DB load and the first scan fails closed with ECONNREFUSED.
      depends_on = ["clamd"]

      ports {
        container_port = 4000
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        startup_cpu_boost = true
      }

      env {
        name  = "NODE_ENV"
        value = "production"
      }
      # Runs the shared backend image in a scanner-only role: the entrypoint skips CA-provider
      # validation for this role, so the scanner never needs (or can mount) the Platform CA key.
      env {
        name  = "APP_ROLE"
        value = "scanner"
      }
      env {
        name  = "QUARANTINE_BUCKET"
        value = local.quarantine_bucket
      }
      # clamd sidecar over the shared localhost network namespace.
      env {
        name  = "CLAMAV_HOST"
        value = "localhost"
      }
      env {
        name  = "CLAMAV_PORT"
        value = "3310"
      }
      # /internal/scan-events accepts only OIDC calls whose identity == this Eventarc SA (fail-closed).
      env {
        name  = "SCAN_EVENTS_SA"
        value = google_service_account.sa_eventarc_scan.email
      }

      dynamic "env" {
        for_each = local.scanner_secret_env
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = "${var.name_prefix}-${env.value}"
              version = "latest"
            }
          }
        }
      }
    }

    # [1] clamd sidecar — the official image runs clamd (TCP 3310) + freshclam. No ingress port.
    # Needs headroom for the signature DB in memory.
    containers {
      name  = "clamd"
      image = var.clamav_image

      # Readiness gate for the scanner-app depends_on above. clamd binds :3310 only after loading
      # ~3.6M signatures into memory (~30-60s cold). Probe the TCP port and allow up to ~3 min
      # before Cloud Run abandons the cold start; the app is held until this passes.
      startup_probe {
        tcp_socket {
          port = 3310
        }
        period_seconds    = 10
        failure_threshold = 18
        timeout_seconds   = 3
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "2Gi"
        }
      }
    }
  }

  # CI deploys the app image; Terraform must not fight it. clamd image stays TF-managed (index 1).
  lifecycle {
    ignore_changes = [template[0].containers[0].image]
  }
}

# ── Eventarc: quarantine object.finalized → scanner /internal/scan-events (OIDC) ──
resource "google_service_account" "sa_eventarc_scan" {
  account_id   = "${var.name_prefix}-sa-evt-scan"
  display_name = "Sweptlock Eventarc scan trigger"
  project      = var.project_id
}

# The trigger SA invokes the scanner…
resource "google_cloud_run_v2_service_iam_member" "evt_invoke_scanner" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.scanner.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.sa_eventarc_scan.email}"
}

# …and must be allowed to receive events.
resource "google_project_iam_member" "evt_receiver" {
  project = var.project_id
  role    = "roles/eventarc.eventReceiver"
  member  = "serviceAccount:${google_service_account.sa_eventarc_scan.email}"
}

# GCS agent publishes object events into the Eventarc Pub/Sub transport.
resource "google_project_iam_member" "gcs_agent_pubsub" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${local.gcs_service_agent}"
}

# At trigger-creation time Eventarc validates the source bucket exists — and it performs that
# check AS the trigger's own service account (sa_eventarc_scan), NOT a Google service agent.
# eventReceiver/run.invoker don't include storage.buckets.get, so trigger creation 403s
# ("Bucket could not be validated") without this. legacyBucketReader is the minimal bucket-scoped
# role carrying storage.buckets.get.
resource "google_storage_bucket_iam_member" "evt_scan_bucket_reader" {
  bucket = google_storage_bucket.quarantine.name
  role   = "roles/storage.legacyBucketReader"
  member = "serviceAccount:${google_service_account.sa_eventarc_scan.email}"
}

resource "google_eventarc_trigger" "scan" {
  name     = "${var.name_prefix}-scan-trigger"
  location = var.region
  project  = var.project_id

  matching_criteria {
    attribute = "type"
    value     = "google.cloud.storage.object.v1.finalized"
  }
  matching_criteria {
    attribute = "bucket"
    value     = google_storage_bucket.quarantine.name
  }

  destination {
    cloud_run_service {
      service = google_cloud_run_v2_service.scanner.name
      region  = var.region
      path    = "/internal/scan-events"
    }
  }

  service_account = google_service_account.sa_eventarc_scan.email

  depends_on = [
    google_project_iam_member.gcs_agent_pubsub,
    google_cloud_run_v2_service_iam_member.evt_invoke_scanner,
    google_storage_bucket_iam_member.evt_scan_bucket_reader,
  ]
}

# ── Cloud Scheduler: hourly cleanup → engine API /internal/run-cleanup (OIDC) ─────
resource "google_service_account" "sa_cleanup" {
  account_id   = "${var.name_prefix}-sa-cleanup"
  display_name = "Sweptlock cleanup scheduler"
  project      = var.project_id
}

# The scheduler SA invokes the ENGINE API (name from the cloud-run unit).
resource "google_cloud_run_v2_service_iam_member" "sched_invoke_api" {
  project  = var.project_id
  location = var.region
  name     = var.api_service_name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.sa_cleanup.email}"
}

resource "google_cloud_scheduler_job" "cleanup" {
  name      = "${var.name_prefix}-guest-cleanup"
  project   = var.project_id
  region    = var.region
  schedule  = var.cleanup_schedule
  time_zone = "Etc/UTC"

  http_target {
    uri         = "${var.api_service_uri}/internal/run-cleanup"
    http_method = "POST"
    oidc_token {
      service_account_email = google_service_account.sa_cleanup.email
      audience              = var.api_service_uri
    }
  }
}
