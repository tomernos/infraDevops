# ── Static external IP ────────────────────────────────────────────────────────
resource "google_compute_address" "api" {
  name    = "${var.name_prefix}-vm-ip"
  region  = var.region
  project = var.project_id
}

# ── Sandbox-only firewall: allow direct access on port 4000 from internet ─────
# Phase 3: this is replaced by a Load Balancer + HTTPS. Remove this rule then.
resource "google_compute_firewall" "allow_api_direct" {
  name    = "${var.name_prefix}-fw-allow-api-direct"
  network = var.vpc_name
  project = var.project_id

  direction = "INGRESS"
  priority  = 1000

  allow {
    protocol = "tcp"
    ports    = ["4000"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["sweptlock-backend"]
}

# ── VM instance ───────────────────────────────────────────────────────────────
resource "google_compute_instance" "api" {
  name         = "${var.name_prefix}-vm-api"
  machine_type = var.machine_type
  zone         = "${var.region}-a"
  project      = var.project_id

  # Tags must match firewall target_tags
  tags = ["allow-iap-ssh", "sweptlock-backend"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 20
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = var.subnet_self_link

    # Public IP — direct access for sandbox. Removed when LB is added in Phase 3.
    access_config {
      nat_ip = google_compute_address.api.address
    }
  }

  # VM runs AS this service account — no key files needed
  service_account {
    email  = var.sa_api_email
    scopes = ["cloud-platform"]
  }

  metadata = {
    startup-script = templatefile("${path.module}/startup.sh.tpl", {
      project_id = var.project_id
      region     = var.region
      name_prefix = var.name_prefix
      image_url  = var.image_url
    })
  }

  allow_stopping_for_update = true
}
