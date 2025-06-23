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