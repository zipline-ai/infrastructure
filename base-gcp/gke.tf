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

resource "google_container_cluster" "control_plane" {
  name     = "controlplane"
  location = "us-west1"

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count       = 1
}

resource "google_container_node_pool" "control_plane_node_pool" {
  name       = "dataplane-pool"
  location   = "us-west1"
  cluster    = google_container_cluster.control_plane.name
  node_count = 2

  node_config {
    preemptible  = true
    machine_type = "c4a-standard-1"
  }
}