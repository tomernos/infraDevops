# Self-hosted GitHub Actions runner as a Cloud Run Job. Two modes, one module.
#
#   runner_mode = "ephemeral"  (default — dev/prod today)
#     One-shot JIT runner for Android builds. .github/workflows/build-android.yml in
#     sweptlock-engine mints a single-use JIT config and executes this Job with it injected as
#     JIT_CONFIG. The agent runs ONE job, then exits → the execution ends → $0 idle.
#
#   runner_mode = "persistent"  (the central `sweptlock-shared` runner)
#     Long-lived, statically-labeled runner started BY HAND when hosted Actions minutes are
#     unavailable. Serves jobs back-to-back until task_timeout. Because the label stays `cloudrun`,
#     the deploy workflows' `runs-on: [self-hosted, cloudrun]` needs no change.
#
# Design / ADR / runbook: ReferencesContext/sweptlock/wiki/04-infra/self-hosted-runner.md
# Shared-project rationale: ReferencesContext/sweptlock/plans/shared-runner-project-design.md
#
# Why the SA + IAM live HERE and not in modules/security: modules/security is shared by several
# envs, but a runner is per-project. Keeping its identity in this stack avoids leaking the
# SA/binding into other environments (module boundary = blast radius). The shared CI project has
# no security stack at all — bootstrap.sh's `shared` case grants the apply SA the
# serviceAccountAdmin it needs for the actAs binding below.

locals {
  registry_host = "${var.region}-docker.pkg.dev"
  runner_image  = "${local.registry_host}/${var.project_id}/${var.name_prefix}-registry/${var.runner_image_name}"

  # Identity that EXECUTES this Job (and therefore needs actAs on sa_runner). Defaults to the
  # same-project engine deploy SA — Terraform-managed in the deploy-identity-engine unit and
  # referenced by its conventional name, not managed here. The central shared runner overrides it:
  # its executor is ANOTHER project's deploy SA (cross-project actAs). Only a principal string, so
  # no dependency on the other project's state.
  executor_sa_email = var.executor_sa_email != "" ? var.executor_sa_email : "${var.name_prefix}-sa-eng-deploy@${var.project_id}.iam.gserviceaccount.com"
  ci_deploy_member  = "serviceAccount:${local.executor_sa_email}"

  is_persistent = var.runner_mode == "persistent"

  # Persistent mode overrides the image's ENTRYPOINT, which is JIT-only and hard-fails without
  # JIT_CONFIG (infra/runner/entrypoint.sh in sweptlock-engine). Registering here instead of in the
  # image means NO image rebuild is needed to add this mode — this mirrors the invocation proven by
  # hand on swpt-mw1-dev-runner-persistent (2026-07-27).
  #   --replace  reclaims the runner name after a previous execution was killed by its timeout
  #              (GitHub keeps the stale registration listed as offline).
  #   NOT --ephemeral: that deregisters after a single job, which is the JIT mode's job.
  # The registration token is short-lived (1h) and is injected PER EXECUTION, never stored here.
  persistent_bootstrap = <<-EOT
    set -euo pipefail
    cd /opt/runner
    : "$${RUNNER_URL:?RUNNER_URL is required}"
    : "$${RUNNER_LABELS:?RUNNER_LABELS is required}"
    : "$${RUNNER_NAME:?RUNNER_NAME is required}"
    if [ "$${RUNNER_REG_TOKEN:-placeholder}" = "placeholder" ]; then
      echo "FATAL: RUNNER_REG_TOKEN is unset or still the stored placeholder." >&2
      echo "       Mint one and inject it as an execution override, e.g.:" >&2
      echo '         TOK=$(gh api -X POST repos/<owner>/<repo>/actions/runners/registration-token --jq .token)' >&2
      echo '         gcloud run jobs execute <job> --update-env-vars RUNNER_REG_TOKEN=$TOK' >&2
      exit 1
    fi
    ./config.sh --url "$RUNNER_URL" --token "$RUNNER_REG_TOKEN" --labels "$RUNNER_LABELS" --name "$RUNNER_NAME" --unattended --replace
    exec ./run.sh
  EOT

  # Ephemeral: JIT_CONFIG is a placeholder only — build-android.yml overrides it per execution via
  # `gcloud run jobs execute --update-env-vars` (an execution override that does NOT mutate this
  # stored definition). The image entrypoint refuses to run without a real JIT value.
  # Persistent: the same override mechanism carries the registration token.
  runner_env = local.is_persistent ? {
    RUNNER_REG_TOKEN = "placeholder"
    RUNNER_URL       = var.runner_url
    RUNNER_LABELS    = var.runner_labels
    RUNNER_NAME      = var.runner_name
    # Baked into the image today; set explicitly so a future image rebuild cannot silently break
    # registration (the agent refuses to run as root without it).
    RUNNER_ALLOW_RUNASROOT = "1"
    } : {
    JIT_CONFIG = "placeholder"
  }
}

# Zero-privilege identity the runner runs as. The runner is COMPUTE, not credentials: pipelines
# that touch GCP authenticate separately via GitHub OIDC → WIF → the target env's deploy SA. So
# this SA deliberately gets no role bindings, and moving the runner between projects needs no new
# deploy-path IAM.
resource "google_service_account" "sa_runner" {
  account_id   = "${var.name_prefix}-sa-runner"
  display_name = "Sweptlock CI build runner"
  description  = "Identity for the Cloud Run Job GitHub runner (no GCP perms needed)"
  project      = var.project_id
}

# Let the executor SA run this Job AS sa_runner. This is the ONLY new IAM: the deploy SA already
# has roles/run.developer (from deploy-identity-engine), so it can already execute Cloud Run Jobs —
# it just needs act-as on sa_runner. For a human-started persistent runner (Owner) this binding is
# not on the critical path, but it keeps a workflow-started runner one step away.
resource "google_service_account_iam_member" "ci_deploy_act_as_runner" {
  service_account_id = google_service_account.sa_runner.name
  role               = "roles/iam.serviceAccountUser"
  member             = local.ci_deploy_member
}

resource "google_cloud_run_v2_job" "runner" {
  name     = "${var.name_prefix}-runner"
  location = var.region
  project  = var.project_id

  # Stateless, Terraform-managed runner — allow IaC to replace/destroy it; the provider default
  # (true) blocks that. See modules/cloud-run-service for rationale.
  deletion_protection = false

  template {
    template {
      service_account       = google_service_account.sa_runner.email
      max_retries           = 0
      timeout               = var.task_timeout
      execution_environment = "EXECUTION_ENVIRONMENT_GEN2" # required for the 8 vCPU / 32GB profile

      containers {
        image = local.runner_image

        # Ephemeral leaves the image ENTRYPOINT in place; persistent replaces it (see
        # local.persistent_bootstrap — the shipped entrypoint is JIT-only).
        command = local.is_persistent ? ["/bin/bash", "-c"] : null
        args    = local.is_persistent ? [local.persistent_bootstrap] : null

        resources {
          limits = {
            cpu    = var.cpu
            memory = var.memory
          }
        }

        dynamic "env" {
          for_each = local.runner_env
          content {
            name  = env.key
            value = env.value
          }
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

    # Fail at plan time, not at registration time: a persistent runner with no URL/name would come
    # up, fail config.sh, and look like a runner problem.
    precondition {
      condition     = var.runner_mode != "persistent" || (var.runner_url != "" && var.runner_name != "")
      error_message = "runner_mode = \"persistent\" requires runner_url and runner_name to be set."
    }
  }
}
