variable "project_id" {
  description = "The GCP project ID"
  type        = string
}
variable "region" {
  description = "The GCP region to deploy resources"
  type        = string
  default     = "us-central1"
}
variable "zone" {
  description = "The GCP zone to deploy resources"
  type        = string
  default     = "us-central1-a"
}
variable "cluster_name" {
  description = "The name of the GKE cluster"
  type        = string
  default     = "logging-cluster"
}
variable "gcs_bucket_name" {
  description = "The name of the GCS bucket for Loki logs"
  type        = string
  default     = null # Will be generated if null
}
variable "network_name" {
  description = "The name of the VPC network"
  type        = string
  default     = "logging-network"
}
variable "subnet_name" {
  description = "The name of the subnet"
  type        = string
  default     = "logging-subnet"
}
variable "subnet_cidr" {
  description = "The CIDR range for the subnet"
  type        = string
  default     = "10.0.0.0/24"
}
variable "node_count" {
  description = "Number of GKE nodes"
  type        = number
  default     = 2
}
variable "machine_type" {
  description = "Machine type for GKE nodes"
  type        = string
  default     = "e2-standard-4"
}
