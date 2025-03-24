locals {
  bucket_name = var.gcs_bucket_name != null ? var.gcs_bucket_name : "loki-logs-${var.project_id}"
}

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
  project                    = var.project_id
  service                    = each.key
  disable_dependent_services = false
  disable_on_destroy         = false
}

resource "google_compute_network" "network" {
  name                    = var.network_name
  auto_create_subnetworks = false
  depends_on              = [google_project_service.services["compute.googleapis.com"]]
}

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

module "gke" {
  source = "./modules/gke"

  project_id           = var.project_id
  cluster_name         = var.cluster_name
  region               = var.region
  network_name         = google_compute_network.network.name
  subnet_name          = google_compute_subnetwork.subnet.name
  pods_range_name      = "${var.subnet_name}-pods"
  services_range_name  = "${var.subnet_name}-services"
  node_pool_name       = "default-node-pool"
  machine_type         = var.machine_type
  node_count           = var.node_count
  node_service_account = google_service_account.gke_sa.email
}

resource "google_storage_bucket" "loki_bucket" {
  name                        = local.bucket_name
  location                    = var.region
  force_destroy               = true
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

resource "google_storage_bucket_iam_binding" "loki_storage_binding" {
  bucket = google_storage_bucket.loki_bucket.name
  role   = "roles/storage.objectAdmin"
  members = [
    "serviceAccount:${google_service_account.loki_sa.email}"
  ]
}

resource "google_pubsub_topic" "gcp_logs" {
  name       = "gcp-logs"
  depends_on = [google_project_service.services["pubsub.googleapis.com"]]
}

resource "google_pubsub_subscription" "vector_logs" {
  name  = "vector-logs-subscription"
  topic = google_pubsub_topic.gcp_logs.name
  # Set message retention duration
  message_retention_duration = "604800s" # 7 days
  # Set acknowledgement deadline
  ack_deadline_seconds = 20
}

resource "google_pubsub_subscription_iam_binding" "vector_pubsub_binding" {
  subscription = google_pubsub_subscription.vector_logs.name
  role         = "roles/pubsub.subscriber"
  members = [
    "serviceAccount:${google_service_account.vector_sa.email}"
  ]
}

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

# Add a service account for GKE nodes
resource "google_service_account" "gke_sa" {
  account_id   = "gke-node-sa"
  display_name = "GKE Node Service Account"
  depends_on   = [google_project_service.services["iam.googleapis.com"]]
}
