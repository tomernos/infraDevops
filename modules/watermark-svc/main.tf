# ── Watermark service runtime SA ─────────────────────────────────────────────
# Deliberately granted NO project roles — the service touches no GCP APIs. Its only
# grant is resource-level accessor on the shared-secret container below (required for
# Cloud Run to mount the secret env at revision creation).
resource "google_service_account" "sa_watermark" {
  account_id   = "${var.name_prefix}-sa-watermark"
  display_name = "Sweptlock Watermark Service"
  description  = "Runtime SA for the internal-only forensic watermark Cloud Run service"
  project      = var.project_id
}

# ── Shared-secret container (container only — value injected out-of-band) ────
# App-level second gate: the API sends X-WM-Auth, the service compares constant-time.
# NEVER a Terraform secret-version, so the value stays out of TF state.
resource "google_secret_manager_secret" "shared_secret" {
  secret_id = "${var.name_prefix}-watermark-shared-secret"
  project   = var.project_id

  replication {
    auto {}
  }

  labels = {
    env    = split("-", var.name_prefix)[2]
    tenant = split("-", var.name_prefix)[0]
  }
}

resource "google_secret_manager_secret_iam_member" "watermark_secret_accessor" {
  secret_id = google_secret_manager_secret.shared_secret.secret_id
  project   = var.project_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.sa_watermark.email}"
}

# ── Optional Terraform-seeded first version ──────────────────────────────────
# The X-WM-Auth shared secret is a pure random bearer token (constant-time compared), so a FRESH env
# can self-seed it here instead of injecting out-of-band. Gated behind var.seed_shared_secret
# (default false) — see the rotation-safety note in variables.tf. In every already-live env this
# stays 0 resources, so TF never moves `latest`. Once a version exists, mount_shared_secret may flip
# true in the same apply. Generator mirrors modules/database's db_password (special=false to avoid
# env/shell escaping; 64 chars for bearer-token headroom).
resource "random_password" "shared_secret" {
  count   = var.seed_shared_secret ? 1 : 0
  length  = 64
  special = false
}

resource "google_secret_manager_secret_version" "shared_secret" {
  count       = var.seed_shared_secret ? 1 : 0
  secret      = google_secret_manager_secret.shared_secret.id
  secret_data = random_password.shared_secret[0].result

  # Belt-and-suspenders against rotation: random_password.result is create-time and persisted in
  # state (no later diff) and ignore_changes guarantees TF never re-writes the value. To make an
  # ALREADY-LIVE env adopt its existing hand-injected version instead of leaving it unmanaged, import
  # it (does NOT rotate) after setting seed_shared_secret=true so the indexed resource exists:
  #   terragrunt import 'google_secret_manager_secret_version.shared_secret[0]' \
  #     "projects/<project>/secrets/<name_prefix>-watermark-shared-secret/versions/<N>"
  lifecycle {
    ignore_changes = [secret_data]
  }
}

# ── Watermark Cloud Run service ──────────────────────────────────────────────
resource "google_cloud_run_v2_service" "watermark" {
  name                = "${var.name_prefix}-watermark"
  location            = var.region
  project             = var.project_id
  ingress             = "INGRESS_TRAFFIC_INTERNAL_ONLY"
  deletion_protection = false # dev

  template {
    service_account = google_service_account.sa_watermark.email
    timeout         = "120s" # rasterizing large PDFs takes time; app deadline is WM_TIMEOUT_S=90s

    scaling {
      min_instance_count = 0
      max_instance_count = var.max_instances
    }

    containers {
      image = var.image_url

      ports {
        container_port = 8000
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      # X-WM-Auth shared secret. Mounted only once the container HAS a version: Terraform creates
      # the container but never the value (out-of-band, as with the drop-zone JWT secret), and a
      # secret_key_ref to a version-less secret fails revision creation. So the bootstrap apply runs
      # with mount_shared_secret=false (service comes up dormant behind internal-only ingress + the
      # IAM invoker binding), the value is injected, then this flips true. Same "empty = not
      # injected" contract modules/cloud-run uses for its own optional env.
      dynamic "env" {
        for_each = var.mount_shared_secret ? { WATERMARK_SHARED_SECRET = google_secret_manager_secret.shared_secret.secret_id } : {}
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = env.value
              version = "latest"
            }
          }
        }
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  # CI deploys new revisions by image — Terraform should not fight CI over the image.
  # `client`/`client_version` are stamped by `deploy-watermark.yml` (`gcloud run services update`) as
  # service metadata; Terraform never sets them, so it would null them on every plan — perpetual
  # cosmetic drift. Ignore them, same as the image (mirrors the api/scanner fix in modules/cloud-run).
  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      client,
      client_version,
    ]
  }

  depends_on = [google_secret_manager_secret_iam_member.watermark_secret_accessor]
}

# ── Invoker — API service account ONLY (no allUsers) ─────────────────────────
resource "google_cloud_run_v2_service_iam_member" "api_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.watermark.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${var.invoker_sa_email}"
}
