output "gke_cluster_name" {
  description = "GKE cluster name"
  value       = module.gke.cluster_name
}

output "gke_cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = module.gke.cluster_endpoint
}

output "gke_cluster_ca_certificate" {
  description = "GKE cluster CA certificate"
  value       = module.gke.cluster_ca_certificate
  sensitive   = true
}

output "gcs_bucket_name" {
  description = "GCS bucket name for Loki"
  value       = google_storage_bucket.loki_bucket.name
}

output "loki_service_account" {
  description = "Loki service account email"
  value       = google_service_account.loki_sa.email
}

output "vector_service_account" {
  description = "Vector service account email"
  value       = google_service_account.vector_sa.email
}

output "pubsub_topic" {
  description = "Pub/Sub topic for GCP logs"
  value       = google_pubsub_topic.gcp_logs.name
}

output "pubsub_subscription" {
  description = "Pub/Sub subscription for Vector"
  value       = google_pubsub_subscription.vector_logs.name
}

output "kubectl_connect_command" {
  description = "Command to connect kubectl to the cluster"
  value       = "gcloud container clusters get-credentials ${module.gke.name} --zone ${var.zone} --project ${var.project_id}"
}
