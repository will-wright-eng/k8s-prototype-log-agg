output "cluster_name" {
  value       = google_container_cluster.cluster.name
  description = "The name of the cluster"
}

output "cluster_endpoint" {
  value       = google_container_cluster.cluster.endpoint
  description = "The IP address of the cluster master"
}

output "cluster_ca_certificate" {
  value       = google_container_cluster.cluster.master_auth[0].cluster_ca_certificate
  description = "The public certificate that is the root of trust for the cluster"
  sensitive   = true
}
