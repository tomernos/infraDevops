# CA pool + a self-signed root CA that issues end-entity PDF-signing certificates. The engine
# issues from the POOL (parent = caPool); CAS routes to an enabled CA. A single root is
# functionally complete for issuance; a subordinate tier (root issues a subordinate, subordinate
# issues leaf) is the recommended rotation-hygiene enhancement — see prod-ca-architecture.md — and
# is a documented follow-up because it needs the CSR sign+activate flow.

resource "google_privateca_ca_pool" "pool" {
  name     = "${var.name_prefix}-ca-pool"
  location = var.region
  project  = var.project_id
  tier     = var.ca_pool_tier

  # Publish the CA cert + CRL so issued leaf certs carry a working CDP for revocation.
  publishing_options {
    publish_ca_cert = true
    publish_crl     = true
  }

  labels = {
    managed_by = "terraform"
    component  = "private-ca"
  }
}

resource "google_privateca_certificate_authority" "root" {
  pool                     = google_privateca_ca_pool.pool.name
  certificate_authority_id = "${var.name_prefix}-root-ca"
  location                 = var.region
  project                  = var.project_id
  deletion_protection      = var.deletion_protection
  type                     = "SELF_SIGNED"
  lifetime                 = var.root_ca_lifetime

  key_spec {
    algorithm = var.root_ca_key_algorithm
  }

  config {
    subject_config {
      subject {
        organization = var.root_ca_organization
        common_name  = var.root_ca_common_name
      }
    }
    x509_config {
      ca_options {
        is_ca = true
      }
      key_usage {
        base_key_usage {
          cert_sign = true
          crl_sign  = true
        }
        extended_key_usage {}
      }
    }
  }
}

# Least-privilege issuance: the runtime SA may request certificates, never administer the CA.
resource "google_privateca_ca_pool_iam_member" "requester" {
  for_each = toset(var.certificate_requester_members)

  # .id (projects/../locations/../caPools/..), NOT .name (short) — the IAM member's ca_pool must be
  # the full resource path or the provider rejects it as an unparseable id.
  ca_pool = google_privateca_ca_pool.pool.id
  role    = "roles/privateca.certificateRequester"
  member  = each.value
}

# The app's startup CA reachability probe calls caPools.get, which certificateRequester does NOT
# include. Rather than grant the broad roles/privateca.auditor (which also exposes certificate
# metadata), define a custom role scoped to exactly that one read — so the runtime SA can verify
# the pool at boot (fail-fast on a misconfigured CAS_CA_POOL) with no extra reach.
# See F3 in backend/src/crypto/providers/gcpCasProvider.js (gcp_cas provider).
resource "google_project_iam_custom_role" "ca_pool_reader" {
  project     = var.project_id
  role_id     = "casCaPoolReader"
  title       = "CAS CA Pool Reader (get only)"
  description = "privateca.caPools.get only — the app's startup CA reachability probe."
  permissions = ["privateca.caPools.get"]
}

resource "google_privateca_ca_pool_iam_member" "pool_reader" {
  for_each = toset(var.certificate_requester_members)

  # Full path via .id (see requester above) — not the short .name.
  ca_pool = google_privateca_ca_pool.pool.id
  role    = google_project_iam_custom_role.ca_pool_reader.id
  member  = each.value
}
