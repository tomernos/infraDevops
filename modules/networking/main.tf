# ── VPC ───────────────────────────────────────────────────────────────────────
resource "google_compute_network" "vpc" {
  name                    = var.vpc_name
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  project                 = var.project_id
}

# ── Subnet ────────────────────────────────────────────────────────────────────
resource "google_compute_subnetwork" "private" {
  name                     = "${var.vpc_name}-subnet-private"
  ip_cidr_range            = var.subnet_cidr
  region                   = var.region
  network                  = google_compute_network.vpc.id
  project                  = var.project_id
  private_ip_google_access = true  # reach Google APIs without leaving Google network

  # Secondary ranges pre-allocated for GKE Autopilot (Phase 5)
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }
}

# ── Cloud Router + NAT ────────────────────────────────────────────────────────
# VMs have no public IP — NAT gives them outbound internet (Firebase, npm, etc.)
resource "google_compute_router" "router" {
  name    = "${var.vpc_name}-router"
  region  = var.region
  network = google_compute_network.vpc.id
  project = var.project_id
}

resource "google_compute_router_nat" "nat" {
  count  = var.enable_nat ? 1 : 0
  name   = "${var.vpc_name}-nat"
  router = google_compute_router.router.name
  region = var.region
  project = var.project_id

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# ── Firewall Rules ────────────────────────────────────────────────────────────

# Allow SSH only from Google IAP (35.235.240.0/20) — no direct port 22 exposure
resource "google_compute_firewall" "allow_iap_ssh" {
  name    = "${var.vpc_name}-fw-allow-iap-ssh"
  network = google_compute_network.vpc.id
  project = var.project_id

  direction = "INGRESS"
  priority  = 1000

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["allow-iap-ssh"]
}

# Allow GCP Load Balancer health checks and traffic to reach backend VMs
resource "google_compute_firewall" "allow_lb" {
  name    = "${var.vpc_name}-fw-allow-lb"
  network = google_compute_network.vpc.id
  project = var.project_id

  direction = "INGRESS"
  priority  = 1000

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  # GCP LB health check source ranges
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["sweptlock-backend"]
}

# ── VPC Peering for Cloud SQL private IP ─────────────────────────────────────
# Cloud SQL with private IP requires VPC peering with servicenetworking.googleapis.com
resource "google_compute_global_address" "private_service_range" {
  name          = "${var.vpc_name}-psc-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 20
  network       = google_compute_network.vpc.id
  project       = var.project_id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_range.name]

  # If re-running after a destroy, wait for the old connection to be removed
  deletion_policy = "ABANDON"
}
