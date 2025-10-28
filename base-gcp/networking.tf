# Deny all other ingress traffic to Dataproc nodes
resource "google_compute_firewall" "deny_other_ingress_to_dataproc" {
  name          = "${var.customer_name}-zipline-deny-other-ingress-to-dataproc"
  network       = var.vpc_network_id != "" ? var.vpc_network_id : google_compute_network.zipline_vpc[0].id
  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["dataproc-node"]
  priority      = 999
  deny {
    protocol = "all"
  }
}

resource "google_compute_firewall" "allow_access_from_dataproc_instances" {
  name          = "${var.customer_name}-zipline-allow-access-from-dataproc-instances"
  network       = var.vpc_network_id != "" ? var.vpc_network_id : google_compute_network.zipline_vpc[0].id
  direction     = "INGRESS"
  source_ranges = ["10.128.0.0/9"]
  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "icmp"
  }
  target_tags = ["dataproc-node"]
  priority    = 998
}

resource "google_compute_network" "zipline_vpc" {
  count                   = var.vpc_network_name == "" ? 1 : 0
  name                    = "${var.customer_name}-zipline-vpc"
  auto_create_subnetworks = false
  project                 = data.google_project.zipline.project_id
}

# Create subnet for Cloud Run services
resource "google_compute_subnetwork" "zipline_subnet" {
  count                    = var.vpc_network_name == "" ? 1 : 0
  name                     = "${var.customer_name}-zipline-subnet"
  ip_cidr_range            = "10.0.0.0/24"
  region                   = var.region
  network                  = google_compute_network.zipline_vpc[0].id
  project                  = data.google_project.zipline.project_id
  private_ip_google_access = true
}

# Create firewall rule to allow internal communication
resource "google_compute_firewall" "zipline_internal" {
  count   = var.vpc_network_name == "" ? 1 : 0
  name    = "${var.customer_name}-zipline-allow-internal"
  network = google_compute_network.zipline_vpc[0].name
  project = data.google_project.zipline.project_id

  allow {
    protocol = "tcp"
    ports    = ["7233", "8080", "3903", "3000", "443", "10250", "80"] # Added service ports
  }

  allow {
    protocol = "icmp"
  }

  # Expanded source ranges for GKE
  source_ranges = [
    "10.0.0.0/24", # Original subnet
  ]
  direction = "INGRESS"
}


# Create firewall rule to allow health checks
resource "google_compute_firewall" "zipline_health_checks" {
  count   = var.vpc_network_name == "" ? 1 : 0
  name    = "${var.customer_name}-zipline-allow-health-checks"
  network = google_compute_network.zipline_vpc[0].name
  project = data.google_project.zipline.project_id

  allow {
    protocol = "tcp"
  }

  source_ranges = [
    "130.211.0.0/22",
    "35.191.0.0/16"
  ] # Google health check ranges
  direction = "INGRESS"
}

# Allocate IP range for private services access
resource "google_compute_global_address" "private_ip_range" {
  count         = var.vpc_network_name == "" ? 1 : 0
  name          = "${var.customer_name}-zipline-private-ip-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.zipline_vpc[0].id
}

# Create private connection for services
resource "google_service_networking_connection" "private_vpc_connection" {
  count                   = var.vpc_network_name == "" ? 1 : 0
  network                 = google_compute_network.zipline_vpc[0].id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_range[0].name]

  depends_on = [
    google_compute_global_address.private_ip_range
  ]
}