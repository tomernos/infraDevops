include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../modules/dns"
}

dependency "compute" {
  config_path = "../compute"
  mock_outputs = {
    external_ip = "0.0.0.0"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

inputs = {
  name_prefix   = "swpt-mw1-sandbox"
  dns_zone_name = "sweptlock-com-sandbox"
  dns_name      = "sweptlock.com."
  subdomain     = "sandbox"
  vm_ip         = dependency.compute.outputs.external_ip
  ttl           = 300
}
