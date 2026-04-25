include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../modules/observability"
}

dependency "compute" {
  config_path = "../compute"
  mock_outputs = {
    health_url = "http://0.0.0.0/api/health"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

inputs = {
  name_prefix        = "swpt-mw1-sandbox"
  health_url         = dependency.compute.outputs.health_url
  alert_emails       = ["tomernos1@gmail.com"]
  monthly_budget_usd = 150
}
