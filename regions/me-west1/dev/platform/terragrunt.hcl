include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  # `//` marks the copy root: terragrunt copies ALL of modules/ into the cache (not just platform/),
  # so the platform module's relative child refs (`../cloud-run-service`) resolve inside the cache.
  source = "../../../../modules//platform"
}

# Reuse the engine's VPC/subnet for Direct VPC Egress → Cloud SQL private IP.
dependency "networking" {
  config_path = "../networking"
  mock_outputs = {
    vpc_id    = "projects/mock/global/networks/mock-vpc"
    subnet_id = "projects/mock/regions/me-west1/subnetworks/mock-subnet"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

inputs = {
  name_prefix         = "swpt-mw1-dev"
  vpc_network         = dependency.networking.outputs.vpc_id
  subnetwork          = dependency.networking.outputs.subnet_id
  max_instances       = 3
  firebase_project_id = "sweptlock-dev-844f2"

  # platform-api image (built from sweptlock-platform/api). Runtime-config only — no build args.
  api_image = "me-west1-docker.pkg.dev/sweptlock-dev-844f2/swpt-mw1-dev-registry/platform-api:63f8203"

  # panel_image (Phase 2 — DONE): built from sweptlock-platform/panel with VITE_PLATFORM_API_URL +
  # VITE_API_BASE_URL baked to the live platform-api URL (63f8203). CORS_ORIGINS auto-tracks the
  # panel service URL via module.panel.uri, so no manual CORS edit is needed.
  panel_image = "me-west1-docker.pkg.dev/sweptlock-dev-844f2/swpt-mw1-dev-registry/platform-panel:63f8203"
}
