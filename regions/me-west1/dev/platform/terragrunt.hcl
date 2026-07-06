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

  # panel_image: TWO-PHASE.
  #   Phase 1 — omit (module defaults to the Cloud Run hello image). Apply creates platform-api;
  #             read its URL from the `platform_api_url` output.
  #   Phase 2 — build sweptlock-platform/panel with VITE_PLATFORM_API_URL=<platform_api_url>,
  #             push, then set panel_image to that tag and re-apply. CORS_ORIGINS auto-tracks the
  #             panel service URL, so no manual CORS edit is needed.
  # panel_image = "me-west1-docker.pkg.dev/sweptlock-dev-844f2/swpt-mw1-dev-registry/platform-panel:af43b74"
}
