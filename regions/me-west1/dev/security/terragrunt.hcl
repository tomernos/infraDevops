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

  # Drop-zone quarantine bucket: adopt the existing bucket into Terraform (first apply imports it)
  # and manage its browser CORS. Origins MUST mirror the API CORS_ORIGIN allowlist
  # (secret swpt-mw1-dev-cors-origin) — see wiki/cors-reference.md. Includes the localhost dev
  # ports so a locally-served drop-zone page can PUT to the dev bucket.
  enable_quarantine_bucket = true
  quarantine_cors_origins = [
    "https://sweptlock-dev-844f2.web.app",
    "https://sweptlock-dev-844f2.firebaseapp.com",
    "https://sweptlock.com",
    "http://localhost:8081",
    "http://localhost:19006",
    "http://localhost:3000",
  ]
}
