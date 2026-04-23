include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../modules/networking"
}

inputs = {
  vpc_name      = "swpt-mw1-sandbox-vpc"
  subnet_cidr   = "10.10.0.0/20"
  pods_cidr     = "10.20.0.0/16"   # reserved — GKE Phase 5
  services_cidr = "10.30.0.0/20"   # reserved — GKE Phase 5
  enable_nat    = true
}
