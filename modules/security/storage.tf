# ── Drop-Zone quarantine bucket ──────────────────────────────────────────────
#
# Guests PUT untrusted files here via V4 signed URLs (browser → GCS directly,
# bypassing the Cloud Run request-size cap). Objects are virus-scanned, held as
# PENDING_APPROVAL, and re-encrypted into the MAIN bucket on approval — raw guest
# bytes are never served and never move between buckets un-encrypted. A lifecycle
# rule hard-deletes anything after 7 days (MUST match dropZoneCleanupJob's
# PENDING_MAX_DAYS). No public access: the runtime SA is the only reader, guests
# only ever hold short-lived signed URLs.
#
# Why this is codified (it was created out-of-band in 2026-06 for drop-zone
# Phase 2): the browser PUT carries `Content-Type` + `x-goog-content-length-range`,
# so the bucket CORS must allow those from every first-party web origin. That CORS
# list drifted from the API allowlist (it was missing the firebaseapp.com origin),
# which broke uploads from that origin — see wiki/cors-reference.md. Managing the
# bucket + its CORS in Terraform keeps the two allowlists from diverging again.
#
# Gated + conditional-import so other envs (e.g. sandbox, which has no such bucket)
# are untouched: an empty for_each ⇒ no resource and no import to fail on.
# `prevent_destroy` means a mismatched ForceNew attribute (e.g. a wrong location)
# fails the plan LOUDLY instead of proposing to replace the live bucket.

locals {
  quarantine_bucket = var.enable_quarantine_bucket ? toset(["${var.name_prefix}-quarantine"]) : toset([])
}

import {
  for_each = local.quarantine_bucket
  id       = "${var.project_id}/${each.value}"
  to       = google_storage_bucket.quarantine[each.key]
}

resource "google_storage_bucket" "quarantine" {
  for_each = local.quarantine_bucket

  name     = each.value
  project  = var.project_id
  location = upper(var.region) # regional; GCS stores the location upper-cased (ME-WEST1)

  storage_class               = "STANDARD"
  uniform_bucket_level_access = true       # IAM-only; no object ACLs
  public_access_prevention    = "enforced" # never publicly reachable
  force_destroy               = false

  # Untrusted guest uploads are ephemeral — scanned + reviewed within days, then
  # re-encrypted into the main bucket. Hard-delete any leftover at 7 days.
  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 7
    }
  }

  # Browser → GCS direct PUT only. Origins MUST mirror the API CORS_ORIGIN
  # allowlist (see wiki/cors-reference.md). Emitted only when origins are given.
  dynamic "cors" {
    for_each = length(var.quarantine_cors_origins) > 0 ? [1] : []
    content {
      origin          = var.quarantine_cors_origins
      method          = ["PUT"]
      response_header = ["Content-Type", "x-goog-content-length-range"]
      max_age_seconds = 3600
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}
