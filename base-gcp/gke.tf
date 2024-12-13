resource "google_service_account" "node_group" {
  account_id   = "node-group"
  display_name = "Node Group Service Account"
}

data "google_project" "project" {
}

resource "google_project_iam_binding" "node_group_access" {
  role = "roles/container.defaultNodeServiceAccount"
  project = data.google_project.project.project_id
  members = [
  "serviceAccount:${google_service_account.node_group.email}",
  ]
}

resource "google_container_cluster" "dataplane" {
  name     = "dataplane-cluster"
  location = var.region

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count       = 1

  service_external_ips_config {
    enabled = false
  }
}

resource "google_container_node_pool" "control_plane_node_pool" {
  name       = "dataplane-pool"
  location   = var.region
  cluster    = google_container_cluster.dataplane.name
  initial_node_count = 1
  autoscaling {
    min_node_count = 1
    max_node_count = 10
  }

  node_config {
    preemptible  = true
    machine_type = "e2-medium"
    disk_type = "pd-standard"
    disk_size_gb = 100
  }
  network_config {
    enable_private_nodes = true
  }
}