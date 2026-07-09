# Activity-log pipeline infra: request → maskPii → Pub/Sub topic → in-process worker → Firestore (TTL).
# Backend: src/services/activityLog.js (publisher) + src/services/activityLogWorker.js (subscriber).
# The topic/subscription names are the backend's hard-coded defaults (no env override is wired on the
# API/scanner), so they are NOT name_prefixed — changing them here silently breaks the data flow.
#
# NOTE: assumes firestore.googleapis.com + pubsub.googleapis.com are enabled on the project (bootstrap
# concern, same convention as the guest-sharing module's eventarc note). Enable once if a plan errors
# with a disabled-service message.

# ── Pub/Sub transport ────────────────────────────────────────────────────────
resource "google_pubsub_topic" "activity_log" {
  name    = var.topic_name
  project = var.project_id
}

resource "google_pubsub_subscription" "writer" {
  name    = var.subscription_name
  topic   = google_pubsub_topic.activity_log.id
  project = var.project_id

  # The worker streaming-pulls and acks per message after the Firestore write; give it headroom.
  ack_deadline_seconds       = 60
  message_retention_duration = "86400s" # keep undelivered events 1 day
  retain_acked_messages      = false

  # Never auto-expire the subscription (default deletes it after 31 days idle → silent data loss).
  expiration_policy {
    ttl = ""
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
}

# ── Firestore (native) — event sink; native TTL handles retention, no cleanup job ──
resource "google_firestore_database" "default" {
  project     = var.project_id
  name        = "(default)"
  location_id = var.firestore_location != "" ? var.firestore_location : var.region
  type        = "FIRESTORE_NATIVE"

  # Abandon (not delete) on destroy — a refactor/teardown must never nuke audit history.
  deletion_policy = "ABANDON"
}

# Retention: Firestore auto-deletes docs whose expireAt < now. The worker stamps expireAt on write
# (ACTIVITY_LOG_RETENTION_HOURS). This enables the TTL policy on that field.
resource "google_firestore_field" "activity_log_ttl" {
  project    = var.project_id
  database   = google_firestore_database.default.name
  collection = var.collection
  field      = "expireAt"

  ttl_config {}
}

# ── IAM — the runtime SA both publishes and consumes, and writes Firestore ───────
resource "google_pubsub_topic_iam_member" "api_publisher" {
  project = var.project_id
  topic   = google_pubsub_topic.activity_log.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${var.sa_api_email}"
}

resource "google_pubsub_subscription_iam_member" "api_subscriber" {
  project      = var.project_id
  subscription = google_pubsub_subscription.writer.name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${var.sa_api_email}"
}

# Firestore reads/writes. datastore.user is the least-privilege role covering Firestore-native docs.
resource "google_project_iam_member" "api_datastore_user" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${var.sa_api_email}"
}
