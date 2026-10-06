include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../modules/security"
}

# Dev-only adoption of resources that were created by hand before Terraform owned them. An import
# block is a no-op once the address is in state, so this file is safe to keep after the first apply.
# It lives here (generated into the dev working dir) rather than in modules/security because prod
# has no such hand-made resource to import.
#
#   sign-guest-jwt-secret: created manually 2026-09-16 to unblock external signers on dev (see
#   ReferencesContext sweptlock/wiki/04-infra/infra-reference.md). Adopting keeps the container
#   and its live version; recreating it would invalidate every in-flight external-signer token.
generate "dev_adoptions" {
  path      = "imports_dev.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOT
    import {
      to = google_secret_manager_secret.secrets["sign-guest-jwt-secret"]
      id = "projects/sweptlock-dev-844f2/secrets/swpt-mw1-dev-sign-guest-jwt-secret"
    }
  EOT
}

inputs = {
  name_prefix = "swpt-mw1-dev"
  # Stage A: create dev-only Platform CA secret containers. Versions are populated via the runbook
  # (out-of-band). Enabled only in dev — sandbox/other envs keep the default (false).
  enable_local_platform_ca_secrets = true

  # KMS + Secret Manager Data Access audit logs (NOW-3 / gap G-03): per-decrypt/per-MAC/
  # per-secret-access trail. See modules/security/audit.tf for scope decisions.
  enable_data_access_audit_logs = true

  # The drop-zone quarantine bucket + its CORS allowlist are owned solely by the guest-sharing stack
  # now (they used to be duplicated here, which caused permanent CORS drift). See
  # modules/security/storage.tf and modules/guest-sharing/main.tf.

  # drop-zone-jwt-secret VALUE: left to the out-of-band runbook here because THIS env's version was
  # already hand-injected and services mount it at `latest` (a TF version would rotate it). A FRESH
  # env may instead self-seed it by uncommenting the next line on its FIRST apply — see the
  # rotation-safety note in modules/security/variables.tf. DO NOT enable it in this live env.
  # seed_drop_zone_jwt_secret = true
}
