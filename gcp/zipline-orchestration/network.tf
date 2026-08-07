locals {
  create_network = local.cloud_args.network == "" && local.cloud_args.subnetwork == ""

  network_self_link    = local.create_network ? google_compute_network.main[0].self_link : data.google_compute_network.main[0].self_link
  subnetwork_self_link = local.create_network ? google_compute_subnetwork.gke[0].self_link : data.google_compute_subnetwork.gke[0].self_link
}

resource "google_compute_network" "main" {
  count = local.create_network ? 1 : 0

  project                 = local.project_id
  name                    = local.network_name
  auto_create_subnetworks = false

  depends_on = [google_project_service.required]
}

resource "google_compute_subnetwork" "gke" {
  count = local.create_network ? 1 : 0

  project                  = local.project_id
  name                     = local.subnetwork_name
  region                   = local.region
  network                  = google_compute_network.main[0].id
  ip_cidr_range            = local.cloud_args.network_cidr
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = local.cloud_args.pods_range_name
    ip_cidr_range = local.cloud_args.pods_range_cidr
  }

  secondary_ip_range {
    range_name    = local.cloud_args.services_range_name
    ip_cidr_range = local.cloud_args.services_range_cidr
  }
}

data "google_compute_network" "main" {
  count = local.create_network ? 0 : 1

  project = local.network_project_id
  name    = local.cloud_args.network
}

data "google_compute_subnetwork" "gke" {
  count = local.create_network ? 0 : 1

  project = local.network_project_id
  name    = local.cloud_args.subnetwork
  region  = local.region
}

resource "google_compute_router" "gke" {
  count = local.create_network && local.cloud_args.private_nodes && local.cloud_args.create_cloud_nat ? 1 : 0

  project = local.project_id
  name    = "${local.name_prefix}-gke-router"
  region  = local.region
  network = google_compute_network.main[0].id
}

resource "google_compute_router_nat" "gke" {
  count = local.create_network && local.cloud_args.private_nodes && local.cloud_args.create_cloud_nat ? 1 : 0

  project                            = local.project_id
  name                               = "${local.name_prefix}-gke-nat"
  router                             = google_compute_router.gke[0].name
  region                             = local.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.gke[0].self_link
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}
