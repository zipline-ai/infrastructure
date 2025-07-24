resource "google_compute_network" "zipline_vpc" {
  name                    = "zipline-vpc"
  auto_create_subnetworks = false
  project                 = data.google_project.zipline.project_id
}

# Create subnet for Cloud Run services
resource "google_compute_subnetwork" "zipline_subnet" {
  name          = "zipline-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.zipline_vpc.id
  project       = data.google_project.zipline.project_id
}

# Create firewall rule to allow internal communication
resource "google_compute_firewall" "zipline_internal" {
  name    = "zipline-allow-internal"
  network = google_compute_network.zipline_vpc.name
  project = data.google_project.zipline.project_id

  allow {
    protocol = "tcp"
    ports    = ["7233", "8080", "3903", "3000"] # Temporal, Temporal UI, Orchestration, Web UI ports
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = ["10.0.0.0/24"] # Allow traffic within the subnet
  direction     = "INGRESS"
}

# Create firewall rule to allow health checks
resource "google_compute_firewall" "zipline_health_checks" {
  name    = "zipline-allow-health-checks"
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
