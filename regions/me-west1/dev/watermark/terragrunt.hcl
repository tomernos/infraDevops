include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../modules/watermark-svc"
}

dependency "security" {
  config_path = "../security"
  mock_outputs = {
    sa_api_email = "mock-sa@mock-project.iam.gserviceaccount.com"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

inputs = {
  name_prefix      = "swpt-mw1-dev"
  invoker_sa_email = dependency.security.outputs.sa_api_email
  max_instances    = 2

  # watermark shared-secret VALUE: left to the out-of-band injection here because THIS env's version
  # was already hand-injected and the service mounts it at `latest` (a TF version would rotate it). A
  # FRESH env may instead self-seed it by uncommenting the next line on its FIRST apply — see the
  # rotation-safety note in modules/watermark-svc/variables.tf. DO NOT enable it in this live env.
  # seed_shared_secret = true
}
