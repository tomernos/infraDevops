include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../modules/security"
}

# FIRST APPLY ONLY: KMS key ring and key do not exist yet in a new project.
# Temporarily comment out both `import` blocks in modules/security/main.tf,
# run `terragrunt apply`, then uncomment them and run apply again (no-op).

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
