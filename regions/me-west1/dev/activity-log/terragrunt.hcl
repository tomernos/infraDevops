include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../modules/activity-log"
}

# Only needs the runtime SA (publisher/subscriber/Firestore writer). Pub/Sub + Firestore are global
# APIs — no VPC dependency, unlike guest-sharing.
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
}
