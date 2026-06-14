include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../modules/database"
}

dependency "networking" {
  config_path = "../networking"
  mock_outputs = {
    vpc_self_link                 = "projects/mock/global/networks/mock-vpc"
    private_service_connection_id = "mock-connection-id"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

inputs = {
  instance_name       = "swpt-mw1-dev-sql-main"
  vpc_self_link       = dependency.networking.outputs.vpc_self_link
  db_name             = "sweptlock_db"
  db_user             = "sweptlock"
  tier                = "db-g1-small"
  disk_size_gb        = 20
  ha_enabled          = false
  pitr_enabled        = false
  deletion_protection = false
}
