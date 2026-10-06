include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../modules/account-lifecycle"
}

# The scheduler job targets the engine API, so the API must exist first. The API learns the
# sweeper SA email as a CONVENTIONAL constant (cloud-run unit input deletion_sweeper_sa), not as a
# dependency output, so the edge stays one-directional — same pattern as guest-sharing's cleanup SA.
dependency "cloud-run" {
  config_path = "../cloud-run"
  mock_outputs = {
    service_name = "swpt-mw1-dev-api"
    service_url  = "https://swpt-mw1-dev-api-mock.a.run.app"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

inputs = {
  name_prefix      = "swpt-mw1-dev"
  api_service_name = dependency.cloud-run.outputs.service_name
  api_service_uri  = dependency.cloud-run.outputs.service_url
}
