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
  instance_name = "swpt-mw1-prod-sql-main"
  vpc_self_link = dependency.networking.outputs.vpc_self_link
  db_name       = "sweptlock_db"
  db_user       = "sweptlock"
  # PROD sizing/hardening (dev = db-g1-small, no HA, no PITR, unprotected).
  tier                = "db-custom-2-4096"
  disk_size_gb        = 50
  ha_enabled          = true # REGIONAL failover replica
  pitr_enabled        = true # point-in-time recovery
  deletion_protection = true # block accidental prod DB destroy
}
