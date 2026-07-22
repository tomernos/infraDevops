locals {
  env = "prod"

  # Prod project id — the same value scripts/bootstrap.sh uses for `prod`. Create
  # this GCP project (+ link billing) BEFORE running bootstrap (see PROD-BRINGUP.md
  # step 1). root.hcl derives the state bucket (swpt-mw1-infra-prod-tf) and the
  # generated provider's project from this. If GCP rejects `sweptlock-prod` as
  # taken, pick a unique id and change it here AND in scripts/bootstrap.sh's prod case.
  project_id = "sweptlock-prod"

  # Database sizing — PRODUCTION posture (dev used db-g1-small / no HA / no PITR).
  sql_tier         = "db-custom-2-4096" # 2 vCPU / 4 GiB; scale from real load
  sql_ha_enabled   = true               # regional HA (failover replica)
  sql_pitr_enabled = true               # point-in-time recovery (WAL archiving)
  sql_backup_days  = 30                 # dev kept 7

  # Cloud Run — do not scale to zero in prod (cold starts on real traffic).
  cloud_run_max_instances = 10
}
