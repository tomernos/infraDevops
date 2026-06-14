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
}
