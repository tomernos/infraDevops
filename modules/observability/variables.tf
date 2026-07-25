variable "project_id"  { type = string }
variable "name_prefix" { type = string }

variable "service_url" {
  type        = string
  description = "Base HTTPS URL of the Cloud Run API (e.g. https://swpt-mw1-dev-api-xxxx.a.run.app)"

  validation {
    condition     = startswith(var.service_url, "https://")
    error_message = "service_url must be an https:// URL — Cloud Run is HTTPS-only."
  }
}

variable "health_path" {
  type        = string
  description = "Path probed by the uptime check. NOTE: /health is deliberately DB-blind; switch to /health/ready once the engine ships it (AD-9 open item #6)."
  default     = "/health"
}

variable "alert_email" {
  type        = string
  description = "Email address for the notification channel. PLACEHOLDER default — set to a real, monitored address before apply."
  default     = "alerts@sweptlock.com"
}

variable "sql_instance_name" {
  type        = string
  description = "Cloud SQL instance name (e.g. swpt-mw1-dev-sql-main). Empty string disables the Cloud SQL alert policies — use that in envs where the instance is intentionally stopped."
  default     = ""
}

variable "sql_connections_threshold" {
  type        = number
  description = "Alert when active backends exceed this. Default 80 = 80% of the max_connections=100 flag set by modules/database."
  default     = 80
}
