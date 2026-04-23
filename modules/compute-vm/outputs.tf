output "external_ip"  { value = google_compute_address.api.address }
output "vm_name"      { value = google_compute_instance.api.name }
output "ssh_command"  {
  value = "gcloud compute ssh ${google_compute_instance.api.name} --zone=${var.region}-a --tunnel-through-iap --project=${var.project_id}"
}
output "health_url"   { value = "http://${google_compute_address.api.address}:4000/health" }
