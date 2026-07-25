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
  name_prefix = "swpt-mw1-prod"
  # PROD uses a REAL CA, never the local dev CA — so the local-CA PEM secret
  # containers are NOT created here (dev-only). Keep this false; wire the real prod
  # CA in the cloud-run stack (ca_provider) per the CA design.
  enable_local_platform_ca_secrets = false

  # KMS + Secret Manager Data Access audit logs (NOW-3 / gap G-03): per-decrypt/per-MAC/
  # per-secret-access trail. Roadmap requires dev+prod; takes effect on the next approved
  # prod apply. See modules/security/audit.tf for scope decisions.
  enable_data_access_audit_logs = true

  # The drop-zone quarantine bucket + its CORS allowlist are owned solely by the guest-sharing stack
  # now (they used to be duplicated here, which caused permanent CORS drift). See
  # modules/security/storage.tf and modules/guest-sharing/main.tf.
}
