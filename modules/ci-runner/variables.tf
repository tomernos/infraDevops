variable "project_id" { type = string }
variable "region" { type = string }

variable "name_prefix" {
  type        = string
  description = "Prefix for all resource names, e.g. swpt-mw1-dev"
}

variable "runner_image_name" {
  type        = string
  default     = "runner:latest"
  description = "Image name:tag inside the env's Artifact Registry repo (<name_prefix>-registry)"
}

variable "executor_sa_email" {
  type        = string
  default     = ""
  description = <<-EOT
    BARE email (no "serviceAccount:" prefix) of the service account that EXECUTES the runner Job.
    It is granted roles/iam.serviceAccountUser on sa-runner so it can run the Job as that identity.

    Default "" derives the same-project engine deploy SA
    (<name_prefix>-sa-eng-deploy@<project_id>) — correct for dev/prod, where the runner and the
    deploy identity live in the same project. The CENTRAL shared runner project MUST set this: its
    executor is another project's deploy SA (cross-project actAs), and the derived same-project name
    does not exist there — an IAM binding naming a nonexistent SA fails at apply.
  EOT
}

variable "runner_mode" {
  type        = string
  default     = "ephemeral"
  description = <<-EOT
    "ephemeral"  — one-shot JIT runner (the image's own entrypoint; JIT_CONFIG injected per
                   execution by build-android.yml). Runs ONE job, exits, scales to zero.
    "persistent" — long-lived, statically-labeled runner. Overrides the container command to
                   register with a short-lived registration token and serve MANY jobs until
                   task_timeout. Started by hand when hosted Actions minutes are unavailable.
  EOT
  validation {
    condition     = contains(["ephemeral", "persistent"], var.runner_mode)
    error_message = "runner_mode must be \"ephemeral\" or \"persistent\"."
  }
}

variable "runner_url" {
  type        = string
  default     = ""
  description = <<-EOT
    persistent mode only. GitHub scope the runner registers against — a repo
    ("https://github.com/SweptLock/sweptlock-engine") or the org ("https://github.com/SweptLock").
    Org scope makes ONE runner serve every repo (engine + infra + platform) and is the point of
    centralizing; repo scope is the proven fallback. This is only the STORED default: it can be
    overridden per execution alongside the token, so switching scope needs no apply.
  EOT
}

variable "runner_labels" {
  type        = string
  default     = "cloudrun"
  description = <<-EOT
    persistent mode only. Comma-separated labels. Must contain `cloudrun` — that is what the deploy
    workflows target with `runs-on: [self-hosted, cloudrun]`. Changing it silently orphans every
    self-hosted job.
  EOT
}

variable "runner_name" {
  type        = string
  default     = ""
  description = <<-EOT
    persistent mode only. Runner name as it appears in GitHub (e.g. "cloudrun-shared"). Keep it
    UNIQUE per runner registered to the same scope: config.sh runs with --replace, so two runners
    sharing a name will evict each other.
  EOT
}

variable "cpu" {
  type        = string
  default     = "8"
  description = "vCPU limit. 8 = the Android/Gradle profile; a deploy-only runner needs ~2."
}

variable "memory" {
  type        = string
  default     = "32Gi"
  description = "Memory limit. 32Gi = the Android/Gradle profile; a deploy-only runner needs ~4Gi."
}

variable "task_timeout" {
  type        = string
  default     = "3600s"
  description = <<-EOT
    Max wall-clock per execution. An ephemeral runner exits on its own well before this. For a
    persistent runner this IS the uptime window — it is killed when the timeout hits, which is the
    intended dead-man's switch against a forgotten idle runner. Cloud Run Jobs allow up to 24h.
  EOT
}
