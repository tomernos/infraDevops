output "vpc_id"        { value = google_compute_network.vpc.id }
output "vpc_self_link" { value = google_compute_network.vpc.self_link }
output "subnet_self_link" { value = google_compute_subnetwork.private.self_link }
output "subnet_id"    { value = google_compute_subnetwork.private.id }

output "private_service_connection_id" {
  value       = google_service_networking_connection.private_vpc_connection.id
  description = "Ensures VPC peering is complete before Cloud SQL is created"
}
