# Deny all other ingress traffic to Dataproc nodes
resource "google_compute_firewall" "deny_other_ingress_to_dataproc" {
  name          = "deny-other-ingress-to-dataproc"
  network       = "default"
  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["dataproc-node"]
  priority      = 999
  deny {
    protocol = "all"
  }
}

resource "google_compute_firewall" "allow_access_from_dataproc_instances" {
  name          = "allow-access-from-dataproc-instances"
  network       = "default"
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


# Add Service Networking API (required for private IP)
resource "google_project_service" "service_networking" {
  service = "servicenetworking.googleapis.com"

  disable_dependent_services = false
  disable_on_destroy         = false
}

resource "google_compute_network" "zipline_vpc" {
  name                    = "${var.customer_name}-zipline-vpc"
  auto_create_subnetworks = false
  project                 = data.google_project.zipline.project_id
}

# Create subnet for Cloud Run services
resource "google_compute_subnetwork" "zipline_subnet" {
  name          = "${var.customer_name}-zipline-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.zipline_vpc.id
  project       = data.google_project.zipline.project_id

  # Add secondary IP ranges for GKE pods and services
  secondary_ip_range {
    range_name    = "gke-pods"
    ip_cidr_range = "10.1.0.0/16"
  }

  secondary_ip_range {
    range_name    = "gke-services"
    ip_cidr_range = "10.2.0.0/16"
  }
}

# Create firewall rule to allow internal communication
resource "google_compute_firewall" "zipline_internal" {
  name    = "${var.customer_name}-zipline-allow-internal"
  network = google_compute_network.zipline_vpc.name
  project = data.google_project.zipline.project_id

  allow {
    protocol = "tcp"
    ports    = ["7233", "8080", "3903", "3000", "443", "10250"] # Added GKE ports
  }

  allow {
    protocol = "icmp"
  }

  # Expanded source ranges for GKE
  source_ranges = [
    "10.0.0.0/24",   # Original subnet
    "10.1.0.0/16",   # GKE pods
    "10.2.0.0/16"    # GKE services
  ]
  direction = "INGRESS"
}


# Create firewall rule to allow health checks
resource "google_compute_firewall" "zipline_health_checks" {
  name    = "${var.customer_name}-zipline-allow-health-checks"
  network = google_compute_network.zipline_vpc.name
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
  name          = "${var.customer_name}-zipline-private-ip-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.zipline_vpc.id
}

# Create private connection for services
resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.zipline_vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_range.name]

  depends_on = [
    google_compute_global_address.private_ip_range
  ]
}