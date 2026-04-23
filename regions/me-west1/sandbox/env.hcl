locals {
  env        = "sandbox"
  project_id = "cryptoshare-e5172"

  # VM sizing (used in compute module — Phase 2)
  vm_machine_type = "e2-standard-2"

  # Database sizing
  sql_tier          = "db-g1-small"
  sql_ha_enabled    = false   # no HA in sandbox — saves ~$70/mo
  sql_pitr_enabled  = false
  sql_backup_days   = 7

  # Feature flags
  use_gke = false  # Phase 5
}
