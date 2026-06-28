locals {
  # Non-secret Platform CA guardrail env — injected only when a provider is selected. The backend's
  # caProvider.js reads ALLOW_LOCAL_CA as the literal string "true", hence the bool→string coercion.
  ca_env = var.ca_provider != "" ? {
    APP_ENV        = var.app_env
    CA_PROVIDER    = var.ca_provider
    ALLOW_LOCAL_CA = var.allow_local_ca ? "true" : "false"
  } : {}

  # Secret-backed CA material — only the local provider needs the extractable cert+key (dev only).
  # gcp_cas (future) issues via the API and needs no PEM secrets here.
  ca_secret_env = var.ca_provider == "local" ? {
    PLATFORM_CA_CERT_PEM = "platform-ca-cert-pem"
    PLATFORM_CA_KEY_PEM  = "platform-ca-key-pem"
  } : {}
}

# ── API Cloud Run service ────────────────────────────────────────────────────
resource "google_cloud_run_v2_service" "api" {
  name     = "${var.name_prefix}-api"
  location = var.region
  project  = var.project_id
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = var.sa_api_email

    scaling {
      min_instance_count = 0
      max_instance_count = var.max_instances
    }

    # Direct VPC Egress — Cloud Run gets a private IP in this subnet and can
    # reach Cloud SQL's private IP without a Serverless VPC Access connector.
    vpc_access {
      network_interfaces {
        network    = var.vpc_network
        subnetwork = var.subnetwork
      }
      # ALL_TRAFFIC (not PRIVATE_RANGES_ONLY): route ALL egress — including public Google APIs
      # (Firebase Admin token + Identity Toolkit) — through the VPC and out via Cloud NAT.
      # With PRIVATE_RANGES_ONLY, public traffic took Cloud Run's default path, which failed to
      # reach www.googleapis.com/oauth2/v4/token ("Premature close") → Firebase getUserByEmail()
      # threw app/invalid-credential → /auth/check-user 500 → returning users bounced to signup.
      # NAT (ALL_SUBNETWORKS_ALL_IP_RANGES) gives Google calls a clean, observable egress road.
      # Network reference: ReferencesContext/sweptlock/wiki/networking.md
      egress = "ALL_TRAFFIC"
    }

    containers {
      image = var.image_url

      ports {
        container_port = 4000
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle          = true # CPU only allocated during request handling
        startup_cpu_boost = true # faster cold starts
      }

      # Secrets injected from Secret Manager by convention:
      # secret name = "${name_prefix}-<key>"
      dynamic "env" {
        for_each = {
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
        }
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

      env {
        name  = "NODE_ENV"
        value = "production"
      }

      # Trust-plan root key. When set, the backend wraps per-owner KEKs via Cloud KMS
      # (gcp_kms provider — root key non-extractable, audited, rotatable) instead of the
      # local SERVER_KEK_MASTER_KEY. Non-secret: a KMS crypto-key resource name, not key
      # material. Access is via the runtime SA's cryptoKeyEncrypterDecrypter binding.
      dynamic "env" {
        for_each = var.kek_kms_key != "" ? { SERVER_KEK_KMS_KEY = var.kek_kms_key } : {}
        content {
          name  = env.key
          value = env.value
        }
      }

      # KMS MAC key version for pdf_sign_events seals (MacSign/MacVerify). Non-secret resource name.
      # Access via the runtime SA's cloudkms.signerVerifier binding. See trust-plan-kms.md.
      dynamic "env" {
        for_each = var.sign_hmac_kms_key != "" ? { SERVER_SIGN_HMAC_KMS_KEY = var.sign_hmac_kms_key } : {}
        content {
          name  = env.key
          value = env.value
        }
      }

      # Platform CA guardrail env (non-secret). Only present when ca_provider is set (dev).
      dynamic "env" {
        for_each = local.ca_env
        content {
          name  = env.key
          value = env.value
        }
      }

      # Platform CA material from Secret Manager — only for the local provider (dev). Same
      # secret_key_ref:latest pattern as the core secrets above; never read via a TF data source.
      dynamic "env" {
        for_each = local.ca_secret_env
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

      # NOTE: do NOT set PORT — Cloud Run reserves it and injects it automatically
      # from ports.container_port (4000 below). Setting it fails with HTTP 400.
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  # CI deploys new revisions by image — Terraform should not fight CI over the image.
  # All other template settings (env vars, scaling, vpc) are still managed by Terraform.
  lifecycle {
    ignore_changes = [template[0].containers[0].image]

    # Mirror backend caProvider.js guardrails at the deploy boundary (fail-closed):
    # the extractable local CA is only ever permitted in dev with an explicit opt-in.
    precondition {
      condition     = !var.allow_local_ca || (var.app_env == "dev" && var.ca_provider == "local")
      error_message = "allow_local_ca=true requires app_env=\"dev\" and ca_provider=\"local\"."
    }
    precondition {
      condition     = var.ca_provider != "local" || var.app_env == "dev"
      error_message = "ca_provider=\"local\" is permitted only when app_env=\"dev\"."
    }
  }
}

# ── Public access — Firebase Auth enforced at app level ──────────────────────
resource "google_cloud_run_v2_service_iam_member" "public_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.api.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# NOTE: the CI deploy SA's roles/run.developer grant is owned by scripts/bootstrap.sh
# (which must create the CI identity out-of-band anyway). It is intentionally NOT
# managed here to avoid duplicating identity ownership across bootstrap + Terraform.
