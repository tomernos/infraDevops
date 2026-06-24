include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../modules/ci-runner"
}

# Ordering only (no outputs consumed): the security stack grants the apply SA
# roles/iam.serviceAccountAdmin, which is required to create this module's
# serviceAccountUser binding on sa-runner. Forcing security first gives that grant
# time to propagate before this stack's SA-level setIamPolicy call.
dependencies {
  paths = ["../security"]
}

# Self-contained: the runner SA + its one IAM binding + the Cloud Run Job all live in this
# module. No cross-stack TF dependencies — the image is referenced by URL (built by
# build-runner-image.yml in sweptlock-engine), the CI deploy SA by its conventional name.
# project_id / region are injected by root.hcl from env.hcl / region.hcl.
inputs = {
  name_prefix = "swpt-mw1-dev"
}
