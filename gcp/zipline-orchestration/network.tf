# Provisions a VPC and regional subnet (with secondary ranges for pods/services)
# when the caller omits gcp.network / gcp.subnet. Reads var.gcp directly rather
# than local.cloud_args so network creation does not cycle through the google
# provider's project/region (both of which the provider block reads).

locals {
  create_network = trimspace(tostring(try(var.gcp.network, ""))) == ""

  network_name = local.create_network ? google_compute_network.main[0].name : trimspace(tostring(try(var.gcp.network, "")))
  subnet_name  = local.create_network ? google_compute_subnetwork.main[0].name : trimspace(tostring(try(var.gcp.subnet, "")))

  network_self_link = local.create_network ? google_compute_network.main[0].self_link : "projects/${local.cloud_args.project_id}/global/networks/${local.network_name}"
  subnet_self_link  = local.create_network ? google_compute_subnetwork.main[0].self_link : "projects/${local.cloud_args.project_id}/regions/${local.cloud_args.region}/subnetworks/${local.subnet_name}"

  # Executors are pod-IP hungry. /16 for pods gives ~32k addresses — size for
  # peak concurrency (R4). /20 nodes gives 4k nodes. /20 services covers 4k.
  node_cidr     = trimspace(tostring(try(var.gcp.node_cidr, "")))     != "" ? var.gcp.node_cidr     : "10.100.0.0/20"
  pods_cidr     = trimspace(tostring(try(var.gcp.pods_cidr, "")))     != "" ? var.gcp.pods_cidr     : "10.112.0.0/16"
  services_cidr = trimspace(tostring(try(var.gcp.services_cidr, ""))) != "" ? var.gcp.services_cidr : "10.128.0.0/20"
}

resource "google_compute_network" "main" {
  count = local.create_network ? 1 : 0

  name                    = "${local.name_prefix}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "main" {
  count = local.create_network ? 1 : 0

  name                     = "${local.name_prefix}-subnet"
  ip_cidr_range            = local.node_cidr
  region                   = local.cloud_args.region
  network                  = google_compute_network.main[0].id
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = local.pods_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = local.services_cidr
  }
}

# PSA peering for Cloud SQL private IP. Reserves a block inside this VPC that
# Google uses for the Cloud SQL producer-side VPC peering.
resource "google_compute_global_address" "psa" {
  count = local.create_network ? 1 : 0

  name          = "${local.name_prefix}-psa"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 20
  network       = google_compute_network.main[0].id
}

resource "google_service_networking_connection" "psa" {
  count = local.create_network ? 1 : 0

  network                 = google_compute_network.main[0].id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.psa[0].name]
}
