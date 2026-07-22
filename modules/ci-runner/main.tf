# Ephemeral self-hosted GitHub Actions runner (Android builds) as a Cloud Run Job.
#
# Spun up per-build by .github/workflows/build-android.yml in sweptlock-engine: that workflow
# mints a single-use JIT runner config and executes THIS job with it injected as JIT_CONFIG.
# The runner runs ONE job, then exits → the job execution ends → scale to zero ($0 idle).
#
# Design / ADR / runbook: ReferencesContext/sweptlock/wiki/self-hosted-runner.md
#
# Why the SA + IAM live HERE and not in modules/security: modules/security is shared by dev AND
# sandbox, but this runner is dev-only. Keeping its identity in this dev-only stack avoids
# leaking the SA/binding into other environments (module boundary = blast radius).

locals {
  registry_host = "${var.region}-docker.pkg.dev"
  runner_image  = "${local.registry_host}/${var.project_id}/${var.name_prefix}-registry/${var.runner_image_name}"

  # The engine deploy SA is Terraform-managed in the deploy-identity-engine unit (modules/deploy-identity).
  # build-android.yml authenticates as it via WIF. Referenced by its conventional name, not managed here.
  ci_deploy_member = "serviceAccount:${var.name_prefix}-sa-eng-deploy@${var.project_id}.iam.gserviceaccount.com"
}

# Zero-privilege identity the runner runs as. The build only talks to GitHub (checkout + upload
# artifact) — it needs NO GCP permissions at runtime, so this SA gets no role bindings.
resource "google_service_account" "sa_runner" {
  account_id   = "${var.name_prefix}-sa-runner"
  display_name = "Sweptlock CI build runner"
  description  = "Identity for the ephemeral Cloud Run Job GitHub runner (no GCP perms needed)"
  project      = var.project_id
}

# Let the engine deploy SA (the WIF identity in build-android.yml) execute this job AS sa_runner.
# This is the ONLY new IAM: sa-eng-deploy already has roles/run.developer (from deploy-identity-engine),
# so it can already execute Cloud Run Jobs — it just needs act-as on sa_runner.
resource "google_service_account_iam_member" "ci_deploy_act_as_runner" {
  service_account_id = google_service_account.sa_runner.name
  role               = "roles/iam.serviceAccountUser"
  member             = local.ci_deploy_member
}

resource "google_cloud_run_v2_job" "runner" {
  name     = "${var.name_prefix}-runner"
  location = var.region
  project  = var.project_id

  # Ephemeral JIT build runner — stateless, Terraform-managed. Allow IaC to replace/destroy it;
  # the provider default (true) blocks that. See modules/cloud-run-service for rationale.
  deletion_protection = false

  template {
    template {
      service_account       = google_service_account.sa_runner.email
      max_retries           = 0
      timeout               = "3600s"
      execution_environment = "EXECUTION_ENVIRONMENT_GEN2" # required for the 8 vCPU / 32GB profile

      containers {
        image = local.runner_image

        resources {
          limits = {
            cpu    = "8"
            memory = "32Gi"
          }
        }

        # Placeholder only — build-android.yml overrides JIT_CONFIG per execution via
        # `gcloud run jobs execute --update-env-vars` (an execution override that does NOT mutate
        # this stored definition). The entrypoint refuses to run without a real JIT value.
        env {
          name  = "JIT_CONFIG"
          value = "placeholder"
        }
      }
    }
  }

  # build-runner-image.yml pushes new :latest tags; let image bumps land without TF drift,
  # mirroring the cloud-run module's image handling. Apply a bump via re-apply of this stack
  # or `gcloud run jobs update <name> --image ...`.
  lifecycle {
    ignore_changes = [
      template[0].template[0].containers[0].image,
    ]
  }
}
