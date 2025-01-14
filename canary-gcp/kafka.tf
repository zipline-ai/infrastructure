data "google_project" "zipline" {
}

# Kafka

resource "google_managed_kafka_cluster" "zipline_kafka" {
  cluster_id = "zipline-kafka-cluster"
  location   = var.region
  project    = data.google_project.zipline.project_id

  capacity_config {
    memory_bytes = 12884901888 # 12 GB
    vcpu_count   = 3
  }

  gcp_config {
    access_config {
      network_configs {
        subnet = "projects/${data.google_project.zipline.number}/regions/${var.region}/subnetworks/default"
      }
    }
  }
}