terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0.0, < 5.0.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.10.0"
    }
  }
  backend "gcs" {
    bucket = "integral-dev-terraform-state"
    prefix = "terraform/k8s-prototype-log-agg/state"
  }
}

data "google_client_config" "default" {}
