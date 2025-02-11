resource "google_service_account" "node_group" {
  account_id   = "node-group"
  display_name = "Node Group Service Account"
}

data "google_project" "project" {
}

resource "google_project_iam_binding" "node_group_access" {
  role    = "roles/container.defaultNodeServiceAccount"
  project = data.google_project.project.project_id
  members = [
    "serviceAccount:${google_service_account.node_group.email}",
  ]
}

resource "google_project_iam_member" "node_group_artifact_registry" {
  project = data.google_project.project.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.node_group.email}"
}

resource "google_project_iam_member" "node_group_kafka" {
  project = data.google_project.project.project_id
  role    = "roles/managedkafka.client"
  member  = "serviceAccount:${google_service_account.node_group.email}"
}

resource "google_container_cluster" "dataplane" {
  name     = "dataplane-cluster"
  location = var.region

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count       = 1

  network = var.network
  service_external_ips_config {
    enabled = false
  }
}

resource "google_container_node_pool" "control_plane_node_pool" {
  name               = "dataplane-pool"
  location           = var.region
  cluster            = google_container_cluster.dataplane.name
  initial_node_count = 1
  autoscaling {
    min_node_count = 1
    max_node_count = 10
  }

  node_config {
    preemptible     = false
    machine_type    = "e2-highmem-2"
    disk_type       = "pd-standard"
    disk_size_gb    = 30
    service_account = google_service_account.node_group.email
  }
  network_config {
    enable_private_nodes = true
  }
}

resource "google_compute_router" "dataplane_router" {
  name    = "zipline-dataplane-router"
  network = var.network
  region = var.region
}

resource "google_compute_router_nat" "dataplane_nat" {
  name         = "zipline-dataplane-nat"
  router       = google_compute_router.dataplane_router.name
  region = var.region
  source_subnetwork_ip_ranges_to_nat = length(var.subnetworks) == 0 ? "ALL_SUBNETWORKS_ALL_IP_RANGES" : "LIST_OF_SUBNETWORKS"
  nat_ip_allocate_option = "AUTO_ONLY"

  dynamic "subnetwork" {
    for_each = var.subnetworks
    content {
      name = subnetwork.value
      source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
    }
  }
}