include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../modules/registry"
}

dependency "security" {
  config_path = "../security"
  mock_outputs = {
    sa_api_email = "mock-sa@mock-project.iam.gserviceaccount.com"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

inputs = {
  name_prefix  = "swpt-mw1-dev"
  sa_api_email = dependency.security.outputs.sa_api_email

  # Cross-project pull: the PROD engine CI deploy SA promotes/pulls images from THIS dev
  # (shared-build) registry, so it needs repo-scoped reader here. Applied with dev credentials (the
  # dev tf-apply SA owns dev-project IAM); the member is only a principal string, so no dependency on
  # prod state. Derived from prod/env.hcl (project_id=sweptlock-prod) + the deploy-identity SA-id
  # convention {name_prefix}-sa-{component}-deploy (component "eng"). Codifies the previously-manual
  # grant; keep the derivation in sync if the prod project id or the eng deploy SA id ever changes.
  extra_reader_sa_emails = [
    "swpt-mw1-prod-sa-eng-deploy@sweptlock-prod.iam.gserviceaccount.com",
  ]
}
