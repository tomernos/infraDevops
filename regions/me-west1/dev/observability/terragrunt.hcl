include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../modules/observability"
}

# Uptime check + 5xx alert target the engine API URL — taken from cloud-run state, not hardcoded.
dependency "cloud_run" {
  config_path = "../cloud-run"
  mock_outputs = {
    service_url = "https://mock-api-exqbi4quaq-zf.a.run.app"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# Cloud SQL down/saturation alerts — the /health endpoint is deliberately DB-blind,
# so these are the ONLY signal when the instance stops.
dependency "database" {
  config_path = "../database"
  mock_outputs = {
    instance_name = "mock-sql-main"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

inputs = {
  name_prefix = "swpt-mw1-dev"
  service_url = dependency.cloud_run.outputs.service_url

  # PLACEHOLDER — alerts@sweptlock.com does not exist yet. Point it at a real,
  # monitored inbox (or the future security@ alias, see roadmap NOW-5) BEFORE apply,
  # otherwise every policy notifies a black hole.
  alert_email = "alerts@sweptlock.com"

  sql_instance_name         = dependency.database.outputs.instance_name
  sql_connections_threshold = 80 # 80% of max_connections=100 (modules/database)
}
