output "ca_pool_name" {
  description = "Full CA pool resource name (projects/<p>/locations/<loc>/caPools/<pool>). Set as the engine CAS_CA_POOL env."
  value       = google_privateca_ca_pool.pool.id
}

output "root_ca_id" {
  description = "Full root CA resource name."
  value       = google_privateca_certificate_authority.root.id
}
