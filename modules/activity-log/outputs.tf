output "topic_name" {
  value = google_pubsub_topic.activity_log.name
}

output "subscription_name" {
  value = google_pubsub_subscription.writer.name
}

output "firestore_database" {
  value = google_firestore_database.default.name
}
