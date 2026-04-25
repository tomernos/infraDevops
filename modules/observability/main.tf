# ── Email notification channel ────────────────────────────────────────────────

resource "google_monitoring_notification_channel" "email" {
  for_each     = toset(var.alert_emails)
  display_name = "Email — ${each.value}"
  type         = "email"
  project      = var.project_id

  labels = {
    email_address = each.value
  }
}

locals {
  channel_ids = [for ch in google_monitoring_notification_channel.email : ch.id]
}

# ── Uptime check ──────────────────────────────────────────────────────────────

resource "google_monitoring_uptime_check_config" "api_health" {
  display_name = "${var.name_prefix}-uptime-api"
  timeout      = "10s"
  period       = "60s"
  project      = var.project_id

  http_check {
    path         = "/api/health"
    port         = 80
    use_ssl      = false
    validate_ssl = false

    accepted_response_status_codes {
      status_value = 200
    }
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = regex("https?://([^/]+)", var.health_url)[0]
    }
  }
}

# ── Alert: uptime failure ─────────────────────────────────────────────────────

resource "google_monitoring_alert_policy" "uptime_failure" {
  display_name = "${var.name_prefix}-alert-uptime-failure"
  combiner     = "OR"
  project      = var.project_id

  notification_channels = local.channel_ids

  conditions {
    display_name = "Uptime check failing"
    condition_threshold {
      filter          = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" resource.type=\"uptime_url\" metric.label.check_id=\"${google_monitoring_uptime_check_config.api_health.uptime_check_id}\""
      duration        = "120s"
      comparison      = "COMPARISON_LT"
      threshold_value = 1

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_NEXT_OLDER"
        cross_series_reducer = "REDUCE_COUNT_FALSE"
        group_by_fields      = ["resource.label.host"]
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }
}

# ── Alert: high API error rate (5xx) ─────────────────────────────────────────

resource "google_monitoring_alert_policy" "error_rate" {
  display_name = "${var.name_prefix}-alert-5xx-rate"
  combiner     = "OR"
  project      = var.project_id

  notification_channels = local.channel_ids

  conditions {
    display_name = "5xx error rate > 2%"
    condition_threshold {
      filter          = "metric.type=\"run.googleapis.com/request_count\" resource.type=\"cloud_run_revision\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.02

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }
}

# ── Alert: VM CPU high ────────────────────────────────────────────────────────

resource "google_monitoring_alert_policy" "vm_cpu" {
  display_name = "${var.name_prefix}-alert-vm-cpu-high"
  combiner     = "OR"
  project      = var.project_id

  notification_channels = local.channel_ids

  conditions {
    display_name = "VM CPU > 80% for 10 min"
    condition_threshold {
      filter          = "metric.type=\"compute.googleapis.com/instance/cpu/utilization\" resource.type=\"gce_instance\" resource.label.project_id=\"${var.project_id}\""
      duration        = "600s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.80

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }
}

# ── Budget alert ──────────────────────────────────────────────────────────────

resource "google_billing_budget" "main" {
  billing_account = data.google_project.main.billing_account
  display_name    = "${var.name_prefix}-budget"

  budget_filter {
    projects = ["projects/${var.project_id}"]
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.monthly_budget_usd)
    }
  }

  threshold_rules {
    threshold_percent = 0.5
    spend_basis       = "CURRENT_SPEND"
  }

  threshold_rules {
    threshold_percent = 0.8
    spend_basis       = "CURRENT_SPEND"
  }

  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "CURRENT_SPEND"
  }

  all_updates_rule {
    monitoring_notification_channels = local.channel_ids
    disable_default_iam_recipients   = false
  }
}

data "google_project" "main" {
  project_id = var.project_id
}
