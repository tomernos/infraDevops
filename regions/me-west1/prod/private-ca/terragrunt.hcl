include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../modules/private-ca"
}

# The runtime API SA is granted certificateRequester on the pool (request certs, not administer).
dependency "security" {
  config_path = "../security"
  mock_outputs = {
    sa_api_email = "mock-sa@mock-project.iam.gserviceaccount.com"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

inputs = {
  name_prefix = "swpt-mw1-prod"

  # Least privilege: sa-api may REQUEST certificates only. CA administration / rotation is a
  # human/break-glass role, never the app SA. See regions/me-west1/prod/prod-ca-architecture.md.
  # PARKED: the root CA was disabled (2026-07-31) and deleted (2026-08-08) by Elad, almost certainly
  # to stop Enterprise-tier CA billing before launch (audit log: DisableCertificateAuthority /
  # DeleteCertificateAuthority). The pool stays. Without this flag any prod apply recreated a NEW
  # root, i.e. a new trust anchor, as a side effect of an unrelated PR. Flip to true in the change
  # that launches prod PDF signing, together with the CAS Data Access audit logs.
  root_ca_enabled = false

  certificate_requester_members = [
    "serviceAccount:${dependency.security.outputs.sa_api_email}",
  ]
}
