# Enable required GCP APIs
resource "google_project_service" "services" {
  for_each = toset([
    "container.googleapis.com",     # GKE
    "storage-api.googleapis.com",   # Cloud Storage
    "pubsub.googleapis.com",        # Pub/Sub
    "secretmanager.googleapis.com", # Secret Manager
    "iam.googleapis.com",           # IAM
    "compute.googleapis.com",       # Compute Engine
    "monitoring.googleapis.com",    # Cloud Monitoring
    "logging.googleapis.com"        # Cloud Logging
  ])
  project = var.project_id
  service = each.key
  disable_dependent_services = false
  disable_on_destroy         = false
}
# Create a VPC network for GKE
resource "google_compute_network" "network" {
  name                    = var.network_name
  auto_create_subnetworks = false
  depends_on              = [google_project_service.services["compute.googleapis.com"]]
}
# Create a subnet for GKE
resource "google_compute_subnetwork" "subnet" {
  name          = var.subnet_name
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.network.id
  # Secondary IP ranges for pods and services
  secondary_ip_range {
    range_name    = "${var.subnet_name}-pods"
    ip_cidr_range = "10.1.0.0/16"
  }
  secondary_ip_range {
    range_name    = "${var.subnet_name}-services"
    ip_cidr_range = "10.2.0.0/16"
  }
}
# Create GKE cluster
module "gke" {
  source                     = "terraform-google-modules/kubernetes-engine/google"
  version                    = "~> 29.0"
  project_id                 = var.project_id
  name                       = var.cluster_name
  region                     = var.region
  zones                      = [var.zone]
  network                    = google_compute_network.network.name
  subnetwork                 = google_compute_subnetwork.subnet.name
  ip_range_pods              = "${var.subnet_name}-pods"
  ip_range_services          = "${var.subnet_name}-services"
  http_load_balancing        = true
  network_policy             = true
  horizontal_pod_autoscaling = true
  remove_default_node_pool   = true
  node_pools = [
    {
      name               = "default-node-pool"
      machine_type       = var.machine_type
      min_count          = var.node_count
      max_count          = var.node_count * 2
      disk_size_gb       = 100
      disk_type          = "pd-standard"
      image_type         = "COS_CONTAINERD"
      auto_repair        = true
      auto_upgrade       = true
      initial_node_count = var.node_count
    }
  ]
  # Enable Workload Identity
  identity_namespace = "${var.project_id}.svc.id.goog"
  depends_on = [
    google_project_service.services["container.googleapis.com"],
    google_compute_subnetwork.subnet
  ]
}
# Create Cloud Storage bucket for Loki
resource "google_storage_bucket" "loki_bucket" {
  name          = local.bucket_name
  location      = var.region
  force_destroy = true
  uniform_bucket_level_access = true
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  depends_on = [google_project_service.services["storage-api.googleapis.com"]]
}
# Create service accounts
resource "google_service_account" "loki_sa" {
  account_id   = "loki-sa"
  display_name = "Loki Service Account"
  depends_on   = [google_project_service.services["iam.googleapis.com"]]
}
resource "google_service_account" "vector_sa" {
  account_id   = "vector-sa"
  display_name = "Vector Service Account"
  depends_on   = [google_project_service.services["iam.googleapis.com"]]
}
# Grant permissions to service accounts
resource "google_storage_bucket_iam_binding" "loki_storage_binding" {
  bucket = google_storage_bucket.loki_bucket.name
  role   = "roles/storage.objectAdmin"
  members = [
    "serviceAccount:${google_service_account.loki_sa.email}"
  ]
}
# Create Pub/Sub topic for logs
resource "google_pubsub_topic" "gcp_logs" {
  name = "gcp-logs"
  depends_on = [google_project_service.services["pubsub.googleapis.com"]]
}
# Create Pub/Sub subscription for Vector
resource "google_pubsub_subscription" "vector_logs" {
  name  = "vector-logs-subscription"
  topic = google_pubsub_topic.gcp_logs.name
  # Set message retention duration
  message_retention_duration = "604800s" # 7 days
  # Set acknowledgement deadline
  ack_deadline_seconds = 20
}
# Grant Vector SA permission to read from Pub/Sub
resource "google_pubsub_subscription_iam_binding" "vector_pubsub_binding" {
  subscription = google_pubsub_subscription.vector_logs.name
  role         = "roles/pubsub.subscriber"
  members = [
    "serviceAccount:${google_service_account.vector_sa.email}"
  ]
}
# Allow GKE to use the service accounts
resource "google_service_account_iam_binding" "loki_workload_identity" {
  service_account_id = google_service_account.loki_sa.name
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[logging/loki-sa]"
  ]
}
resource "google_service_account_iam_binding" "vector_workload_identity" {
  service_account_id = google_service_account.vector_sa.name
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[logging/vector-sa]"
  ]
}
# Generate bucket name if not provided
locals {
  bucket_name = var.gcs_bucket_name != null ? var.gcs_bucket_name : "loki-logs-${var.project_id}"
}
