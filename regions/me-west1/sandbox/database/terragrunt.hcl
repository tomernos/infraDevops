include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../modules/database"
}

# Wait for networking before creating Cloud SQL (needs VPC peering to be ready)
dependency "networking" {
  config_path = "../networking"

  # Mock values used during init/plan before networking is applied.
  # Once networking is applied, real outputs replace these automatically.
  mock_outputs = {
    vpc_self_link                    = "projects/mock/global/networks/mock-vpc"
    private_service_connection_id    = "mock-connection-id"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  instance_name   = "swpt-mw1-sandbox-sql-main"
  vpc_self_link   = dependency.networking.outputs.vpc_self_link
  db_name         = "aladin_db"
  db_user         = "sweptlock"
  tier            = "db-g1-small"
  disk_size_gb    = 20
  ha_enabled      = false
  pitr_enabled    = false

  # sandbox: allow terraform destroy without extra steps
  deletion_protection = false
}
