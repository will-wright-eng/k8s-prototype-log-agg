# GKE cluster module
resource "google_container_cluster" "cluster" {
  name                     = var.cluster_name
  location                 = var.region
  project                  = var.project_id
  network                  = var.network_name
  subnetwork               = var.subnet_name
  remove_default_node_pool = true
  initial_node_count       = 1

  # Configure networking
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  # Enable workload identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Enable various GKE features
  addons_config {
    http_load_balancing {
      disabled = false
    }
    network_policy_config {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
  }
}

# Node pool definition
resource "google_container_node_pool" "primary_nodes" {
  name       = var.node_pool_name
  location   = var.region
  cluster    = google_container_cluster.cluster.name
  project    = var.project_id
  node_count = var.node_count

  autoscaling {
    min_node_count = var.node_count
    max_node_count = var.node_count * 2
  }

  node_config {
    machine_type = var.machine_type
    disk_size_gb = 100
    disk_type    = "pd-standard"
    image_type   = "COS_CONTAINERD"

    # Enable workload identity at node level
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    # Google recommends custom service accounts that have cloud-platform scope and permissions granted via IAM Roles.
    service_account = var.node_service_account
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}
