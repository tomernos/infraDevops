variable "project_id"   { type = string }
variable "region"       { type = string }
variable "name_prefix"  { type = string }

variable "health_url" {
  type        = string
  description = "Full URL for the uptime check (e.g. http://1.2.3.4/api/health)"
}

variable "alert_emails" {
  type        = list(string)
  description = "Email addresses to notify on alerts"
}

variable "monthly_budget_usd" {
  type        = number
  description = "Monthly spend threshold in USD before budget alerts fire"
  default     = 150
}
