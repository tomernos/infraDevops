include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../modules/networking"
}

inputs = {
  vpc_name      = "swpt-mw1-dev-vpc"
  subnet_cidr   = "10.11.0.0/20"
  pods_cidr     = "10.21.0.0/16"
  services_cidr = "10.31.0.0/20"
  enable_nat    = true
}
