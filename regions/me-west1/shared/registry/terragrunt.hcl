include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../modules/registry"
}

# No `security` dependency: this project has no security stack (see ../env.hcl). bootstrap.sh's
# `shared` case grants the apply SA artifactregistry.admin directly.
inputs = {
  name_prefix = "swpt-mw1-shared"

  # Deliberately no sa_api_email — nothing here serves the API. The runner Job pulls its image via
  # this project's Cloud Run service agent, which reads in-project registries by default.

  # RUNNER IMAGES ONLY. build-runner-image.yml (sweptlock-engine) authenticates via DEV WIF as the
  # dev engine deploy SA and pushes here, so that SA needs repo-scoped writer on THIS registry.
  # Derived from dev/env.hcl (project_id=sweptlock-dev-844f2) + the deploy-identity SA-id convention
  # {name_prefix}-sa-{component}-deploy (component "eng"); keep in sync if either ever changes.
  extra_writer_sa_emails = [
    "swpt-mw1-dev-sa-eng-deploy@sweptlock-dev-844f2.iam.gserviceaccount.com",
  ]
}
