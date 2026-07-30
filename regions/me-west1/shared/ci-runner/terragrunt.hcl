include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../modules/ci-runner"
}

# Ordering only (no outputs consumed): the Job's image is referenced by convention-derived URL
# (<region>-docker.pkg.dev/<project>/swpt-mw1-shared-registry/runner:latest), so the repo must exist
# first. Unlike dev there is no ../security to depend on — bootstrap.sh's `shared` case grants the
# apply SA roles/iam.serviceAccountAdmin for the sa-runner actAs binding.
dependencies {
  paths = ["../registry"]
}

inputs = {
  name_prefix = "swpt-mw1-shared"
  runner_mode = "persistent"

  # CROSS-PROJECT: the executor is the DEV engine deploy SA, because deploy power stays in the target
  # project and only the worker moves here. The module's same-project default
  # (swpt-mw1-shared-sa-eng-deploy@sweptlock-shared) does not exist — leaving it unset fails the apply.
  executor_sa_email = "swpt-mw1-dev-sa-eng-deploy@sweptlock-dev-844f2.iam.gserviceaccount.com"

  # Registration scope. Repo scope (engine) is the PROVEN configuration and the safe default here.
  # Org scope — "https://github.com/SweptLock" — makes one runner serve engine + infra + platform and
  # is where this is headed; it needs an org-level registration token, so it is switchable at
  # EXECUTION time (override RUNNER_URL alongside RUNNER_REG_TOKEN) without touching Terraform.
  runner_url = "https://github.com/SweptLock/sweptlock-engine"

  # `cloudrun` is what deploy-backend/deploy-frontend target via runs-on: [self-hosted, cloudrun].
  runner_labels = "cloudrun"

  # Distinct from the dev box's `cloudrun-dev`: config.sh --replace would otherwise evict it.
  runner_name = "cloudrun-shared"

  # Deploy/terragrunt work, not Gradle — the module's 8 vCPU / 32Gi Android profile is overkill.
  # Bump both if Android builds ever migrate onto this runner.
  cpu    = "2"
  memory = "4Gi"

  # 6h uptime window per execution, then Cloud Run kills it. Deliberate dead-man's switch: a
  # forgotten runner is both idle spend and a long-lived box trusted by CI.
  task_timeout = "21600s"
}
