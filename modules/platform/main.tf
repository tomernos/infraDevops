# Platform admin composition — wires the shared runtime identity and instantiates the generic
# cloud-run-service module twice (api + panel). No service plumbing lives here; the reusable
# primitive is modules/cloud-run-service.
#
#   * platform-api   — Express; verifies Firebase tokens + reads/writes the SAME sweptlock_db
#                      directly over the private VPC (never through the engine API).
#   * platform-panel — static Vite SPA on nginx; public, but every privileged action is gated at
#                      the API by a Firebase token AND a platform_role. Bundle holds only public
#                      Firebase web config.

locals {
  api_name   = "${var.name_prefix}-platform-api"
  panel_name = "${var.name_prefix}-platform-panel"

  db_secret_keys = ["db-host", "db-port", "db-name", "db-user", "db-password"]
}

# ── Least-privilege runtime identities (separation of concerns) ───────────────
# Two SAs, not one, named symmetrically (-sa-platform-api / -sa-platform-panel). The API is the only
# privileged workload (DB secrets + Firebase admin). The panel is a PUBLIC static nginx server that
# serves files and never touches a secret or Firebase — giving it the API's identity would mean a
# panel-image compromise inherits DB creds + Firebase admin. So the panel runs as its OWN identity with
# ZERO role bindings: least privilege by construction (a compromised panel can act as nobody).
resource "google_service_account" "api" {
  project      = var.project_id
  account_id   = "${var.name_prefix}-sa-platform-api"
  display_name = "SweptLock platform-api runtime SA (DB secrets + Firebase admin)"
}

# Panel runtime identity — intentionally NO IAM bindings anywhere. Do not grant it anything.
resource "google_service_account" "panel" {
  project = var.project_id
  # GCP caps account_id at 30 chars. `${prefix}-sa-platform-panel` is exactly 30 for dev but 31
  # for the longer prod prefix. Keep the full name WHERE IT FITS so existing envs (dev) are
  # byte-identical — no live SA recreation — and fall back to the shorter `-sa-plat-panel` only
  # where it would overflow (prod, and any future longer-prefixed env).
  account_id   = length("${var.name_prefix}-sa-platform-panel") <= 30 ? "${var.name_prefix}-sa-platform-panel" : "${var.name_prefix}-sa-plat-panel"
  display_name = "SweptLock platform-panel runtime SA (static SPA — no permissions)"
}

# Per-secret access to the shared DB credentials (not project-wide) to keep the blast radius tight.
resource "google_secret_manager_secret_iam_member" "db_secrets" {
  for_each  = toset(local.db_secret_keys)
  project   = var.project_id
  secret_id = "${var.name_prefix}-${each.value}"
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.api.email}"
}

# Firebase Auth user management (suspend/disable/delete) + token verification via Application
# Default Credentials — no exported key. Verification alone needs no role; the writes need this one.
resource "google_project_iam_member" "firebase_auth_admin" {
  project = var.project_id
  role    = "roles/firebaseauth.admin"
  member  = "serviceAccount:${google_service_account.api.email}"
}

# ── platform-panel (static nginx SPA) ────────────────────────────────────────
module "panel" {
  source = "../cloud-run-service"

  project_id            = var.project_id
  region                = var.region
  service_name          = local.panel_name
  image                 = var.panel_image
  service_account_email = google_service_account.panel.email # dedicated zero-permission identity
  container_port        = 80                                 # nginx-spa.conf listens on 80
  memory                = "256Mi"
  max_instances         = var.max_instances
  allow_public_invoke   = true
}

# ── platform-api (Express + private DB) ──────────────────────────────────────
module "api" {
  source = "../cloud-run-service"

  project_id            = var.project_id
  region                = var.region
  service_name          = local.api_name
  image                 = var.api_image
  service_account_email = google_service_account.api.email
  container_port        = 8080
  max_instances         = var.max_instances
  allow_public_invoke   = true

  enable_vpc  = true
  vpc_network = var.vpc_network
  subnetwork  = var.subnetwork
  vpc_egress  = "ALL_TRAFFIC" # DB private IP + Firebase public APIs via Cloud NAT

  env_vars = {
    BIND_HOST           = "0.0.0.0" # index.js defaults to 127.0.0.1 — unreachable on Cloud Run
    NODE_ENV            = "production"
    FIREBASE_PROJECT_ID = var.firebase_project_id
    CORS_ORIGINS        = module.panel.uri # single api←panel edge; SPA origin allow-list
  }

  # node-postgres reads PG* when no connectionString is set (config/db.js passes
  # connectionString: process.env.DATABASE_URL, unset here). Reuses the engine's DB secrets —
  # no DATABASE_URL secret, no duplicated password.
  secret_env = {
    PGHOST     = "${var.name_prefix}-db-host"
    PGPORT     = "${var.name_prefix}-db-port"
    PGDATABASE = "${var.name_prefix}-db-name"
    PGUSER     = "${var.name_prefix}-db-user"
    PGPASSWORD = "${var.name_prefix}-db-password"
  }

  depends_on = [google_secret_manager_secret_iam_member.db_secrets]
}
