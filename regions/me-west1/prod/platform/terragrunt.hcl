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
  name_prefix   = "swpt-mw1-prod"
  vpc_network   = dependency.networking.outputs.vpc_id
  subnetwork    = dependency.networking.outputs.subnet_id
  max_instances = 10
  # If prod consolidates Firebase into the prod GCP project (as dev did into 844f2),
  # this equals project_id. If prod uses a SEPARATE Firebase project, set it here.
  firebase_project_id = "sweptlock-prod"

  # Image tags are runtime-config the Platform deploy pipeline (Sweptlock-Platform,
  # _PROD secrets) updates on each release. BOOTSTRAP ONLY: the first apply needs a
  # pullable image, so seed the public Cloud Run hello image. The cloud-run-service
  # module's lifecycle{ignore_changes=[image]} then hands ownership to CI — the real
  # prod digest is set by the platform deploy pipeline and never reverts to hello.
  api_image   = "us-docker.pkg.dev/cloudrun/container/hello"
  panel_image = "us-docker.pkg.dev/cloudrun/container/hello"
}
