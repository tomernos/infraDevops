variable "project_id" { type = string }
variable "region" { type = string }
variable "name_prefix" { type = string }

variable "sa_api_email" {
  type        = string
  description = "Runtime API/scanner service account (from the security unit). Publishes activity events, pulls the writer subscription, and writes the Firestore sink."
}

variable "topic_name" {
  type        = string
  default     = "activity-log"
  description = "Pub/Sub topic. MUST match the backend's ACTIVITY_LOG_TOPIC (activityLog.js default 'activity-log'); no env override is set on the services, so keep this literal."
}

variable "subscription_name" {
  type        = string
  default     = "activity-log-writer"
  description = "Pull subscription the worker streams. MUST match backend ACTIVITY_LOG_SUBSCRIPTION (activityLogWorker.js default 'activity-log-writer')."
}

variable "collection" {
  type        = string
  default     = "activity_log"
  description = "Firestore collection the worker writes (activityLogWorker COLLECTION = 'activity_log')."
}

variable "firestore_location" {
  type        = string
  default     = ""
  description = "Firestore native DB location. Empty ⇒ var.region (me-west1, verified a supported Firestore location)."
}
