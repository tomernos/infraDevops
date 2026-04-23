include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../modules/security"
}

inputs = {
  name_prefix = "swpt-mw1-sandbox"
}
