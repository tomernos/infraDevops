# ── Cloud DNS Managed Zone ────────────────────────────────────────────────────
# One zone per project (shared across envs when using a shared project).
# For sandbox, the zone lives here; prod zone moves to swpt-shared project in Phase 4.

resource "google_dns_managed_zone" "main" {
  name        = var.dns_zone_name
  dns_name    = var.dns_name
  description = "Sweptlock — managed by Terraform"
  project     = var.project_id

  # DNSSEC disabled for now — enable in prod (Phase 4)
  dnssec_config {
    state = "off"
  }
}

# ── A Records ─────────────────────────────────────────────────────────��───────

locals {
  # apex record when subdomain is empty, subdomain record otherwise
  fqdn = var.subdomain == "" ? var.dns_name : "${var.subdomain}.${var.dns_name}"
}

# Main app record (e.g. sandbox.sweptlock.com → VM IP)
resource "google_dns_record_set" "app" {
  name         = local.fqdn
  type         = "A"
  ttl          = var.ttl
  managed_zone = google_dns_managed_zone.main.name
  project      = var.project_id
  rrdatas      = [var.vm_ip]
}

# www redirect record — points to same IP
resource "google_dns_record_set" "www" {
  count        = var.subdomain == "" ? 1 : 0
  name         = "www.${var.dns_name}"
  type         = "A"
  ttl          = var.ttl
  managed_zone = google_dns_managed_zone.main.name
  project      = var.project_id
  rrdatas      = [var.vm_ip]
}

# CAA record — only Let's Encrypt and Google-managed certs allowed
resource "google_dns_record_set" "caa" {
  name         = var.dns_name
  type         = "CAA"
  ttl          = 3600
  managed_zone = google_dns_managed_zone.main.name
  project      = var.project_id
  rrdatas = [
    "0 issue \"pki.goog\"",
    "0 issue \"letsencrypt.org\"",
  ]
}
