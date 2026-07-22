# Generic, reusable Cloud Run v2 service. Not specific to any one app — parameterize per service:
# with/without Direct VPC egress, with/without secret env, public or private invoke, custom port,
# CPU/memory, and arbitrary plain + secret env. Compose it (call it N times) from a stack or a
# higher-level module. The container IMAGE is owned by CI, not Terraform: `var.image` seeds the
# service on first create, but `lifecycle.ignore_changes` (below) then hands ownership of the running
# image to the app's deploy pipeline — the same division the engine module uses. This keeps a
# `terragrunt apply` from reverting a CI-deployed revision, and keeps drift-detect quiet on deploys.

resource "google_cloud_run_v2_service" "this" {
  name     = var.service_name
  location = var.region
  project  = var.project_id
  ingress  = var.ingress

  # Stateless (image in Artifact Registry, config in Terraform) — let IaC own the full lifecycle.
  # The provider defaults this to true, which blocks Terraform-managed replacement (e.g. re-creating
  # a tainted first-apply). Protection here comes from plan review + state, not the GCP flag.
  deletion_protection = false

  template {
    service_account = var.service_account_email

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    # Direct VPC Egress — only when the service needs to reach private resources (e.g. Cloud SQL
    # private IP). egress = ALL_TRAFFIC also routes public calls (Google APIs) through the VPC/NAT.
    dynamic "vpc_access" {
      for_each = var.enable_vpc ? [1] : []
      content {
        network_interfaces {
          network    = var.vpc_network
          subnetwork = var.subnetwork
        }
        egress = var.vpc_egress
      }
    }

    containers {
      image = var.image

      ports {
        container_port = var.container_port
      }

      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      # Plain (non-secret) env.
      dynamic "env" {
        for_each = var.env_vars
        content {
          name  = env.key
          value = env.value
        }
      }

      # Secret env: ENV_NAME => Secret Manager secret id (always :latest).
      dynamic "env" {
        for_each = var.secret_env
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
  # Mirrors modules/cloud-run (the engine service). `var.image` still seeds the first apply.
  lifecycle {
    ignore_changes = [template[0].containers[0].image]
  }
}

# Optional public (unauthenticated) invoke. Services that enforce auth at the app layer set this
# true; private/internal services leave it false and grant run.invoker to specific principals.
resource "google_cloud_run_v2_service_iam_member" "public_invoker" {
  count    = var.allow_public_invoke ? 1 : 0
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.this.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
