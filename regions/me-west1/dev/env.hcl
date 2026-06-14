locals {
  env        = "dev"
  project_id = "sweptlock-dev-844f2"

  # Database sizing — mirrors prod tier, not sandbox's db-g1-small
  sql_tier          = "db-g1-small"   # bump to db-custom-2-4096 for prod
  sql_ha_enabled    = false
  sql_pitr_enabled  = false
  sql_backup_days   = 7

  # Cloud Run — scale to zero when idle
  cloud_run_max_instances = 3
}
