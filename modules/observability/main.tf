# modules/observability — minimum viable telemetry (AD-9).
#
# Provisions: one email notification channel, an HTTPS uptime check on the API
# health endpoint, and alert policies for uptime failure, Cloud Run 5xx ratio,
# Cloud SQL down, and Cloud SQL connection saturation.
#
# Rewritten 2026-07 for the Cloud Run era. The previous (never-applied) version
# targeted the retired VM stack — HTTP port-80 check on /api/health, a
# gce_instance CPU alert — and its uptime alert fired on SUCCESS (COMPARISON_LT
# on a count-of-failures reducer). History has the old version if needed.
#
# SLO strawman this baseline serves (AD-9): API 99.9% monthly · p95 < 400 ms ·
# sign flow p95 < 2 s. Latency-SLO burn alerts are a deliberate follow-up.

locals {
  service_host = regex("https://([^/]+)", var.service_url)[0]
  channel_ids  = [google_monitoring_notification_channel.email.id]
  sql_enabled  = var.sql_instance_name != ""
}

# ── Email notification channel ────────────────────────────────────────────────

resource "google_monitoring_notification_channel" "email" {
  display_name = "${var.name_prefix}-email-alerts"
  type         = "email"
  project      = var.project_id

  labels = {
    email_address = var.alert_email
  }
}

# ── Uptime check: API /health over HTTPS ──────────────────────────────────────

resource "google_monitoring_uptime_check_config" "api_health" {
  display_name = "${var.name_prefix}-uptime-api"
  timeout      = "10s"
  period       = "60s"
  project      = var.project_id

  http_check {
    path         = var.health_path
    port         = 443
    use_ssl      = true
    validate_ssl = true

    accepted_response_status_codes {
      status_value = 200
    }
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = local.service_host
    }
  }
}

# ── Alert: uptime failure ─────────────────────────────────────────────────────
# Canonical uptime alert shape: REDUCE_COUNT_FALSE counts checker regions whose
# latest check FAILED; fire when more than one region agrees, for 2 minutes.

resource "google_monitoring_alert_policy" "uptime_failure" {
  display_name = "${var.name_prefix}-alert-uptime-failure"
  combiner     = "OR"
  project      = var.project_id

  notification_channels = local.channel_ids

  documentation {
    content   = "API uptime check on ${var.service_url}${var.health_path} is failing from multiple regions. NOTE: /health is DB-blind — a stopped DB still passes; check Cloud SQL separately."
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "Uptime check failing"
    condition_threshold {
      filter          = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" resource.type=\"uptime_url\" metric.label.check_id=\"${google_monitoring_uptime_check_config.api_health.uptime_check_id}\""
      duration        = "120s"
      comparison      = "COMPARISON_GT"
      threshold_value = 1

      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_NEXT_OLDER"
        cross_series_reducer = "REDUCE_COUNT_FALSE"
        group_by_fields      = ["resource.label.host"]
      }

      trigger {
        count = 1
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }
}

# ── Alert: Cloud Run 5xx ratio ────────────────────────────────────────────────
# True error RATIO: 5xx requests over all requests, per service, project-wide
# (covers the API and the watermark service alike). No traffic → no series → no
# alert, which is correct for scale-to-zero dev.

resource "google_monitoring_alert_policy" "error_rate" {
  display_name = "${var.name_prefix}-alert-5xx-ratio"
  combiner     = "OR"
  project      = var.project_id

  notification_channels = local.channel_ids

  documentation {
    content   = "A Cloud Run service is returning >5% 5xx for 5 minutes. SLO context (AD-9): API 99.9% monthly."
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "5xx ratio > 5% for 5 min"
    condition_threshold {
      filter             = "metric.type=\"run.googleapis.com/request_count\" resource.type=\"cloud_run_revision\" metric.label.response_code_class=\"5xx\""
      denominator_filter = "metric.type=\"run.googleapis.com/request_count\" resource.type=\"cloud_run_revision\""
      duration           = "300s"
      comparison         = "COMPARISON_GT"
      threshold_value    = 0.05

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["resource.label.service_name"]
      }

      denominator_aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["resource.label.service_name"]
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }
}

# ── Alert: Cloud SQL down ─────────────────────────────────────────────────────
# Compensates for the DB-blind /health: the uptime check stays green when the
# instance is stopped, this fires. Disabled when sql_instance_name = "".

resource "google_monitoring_alert_policy" "sql_down" {
  count        = local.sql_enabled ? 1 : 0
  display_name = "${var.name_prefix}-alert-sql-down"
  combiner     = "OR"
  project      = var.project_id

  notification_channels = local.channel_ids

  documentation {
    content   = "Cloud SQL instance ${var.sql_instance_name} reports down. The API /health check will NOT catch this (DB-blind by design)."
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "database/up < 1 for 5 min"
    condition_threshold {
      filter          = "metric.type=\"cloudsql.googleapis.com/database/up\" resource.type=\"cloudsql_database\" resource.label.database_id=\"${var.project_id}:${var.sql_instance_name}\""
      duration        = "300s"
      comparison      = "COMPARISON_LT"
      threshold_value = 1

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MAX"
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }
}

# ── Alert: Cloud SQL connection saturation ────────────────────────────────────

resource "google_monitoring_alert_policy" "sql_connections" {
  count        = local.sql_enabled ? 1 : 0
  display_name = "${var.name_prefix}-alert-sql-connections"
  combiner     = "OR"
  project      = var.project_id

  notification_channels = local.channel_ids

  documentation {
    content   = "Active backends on ${var.sql_instance_name} exceed ${var.sql_connections_threshold} (max_connections is 100 per modules/database). Look for connection leaks or pool misconfiguration before the hard limit rejects logins."
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "num_backends > ${var.sql_connections_threshold} for 5 min"
    condition_threshold {
      filter          = "metric.type=\"cloudsql.googleapis.com/database/postgresql/num_backends\" resource.type=\"cloudsql_database\" resource.label.database_id=\"${var.project_id}:${var.sql_instance_name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = var.sql_connections_threshold

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_MEAN"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["resource.label.database_id"]
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }
}
