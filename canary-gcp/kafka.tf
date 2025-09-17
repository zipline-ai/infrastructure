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
        subnet = "projects/${data.google_project.zipline.number}/regions/${var.region}/subnetworks/${google_compute_subnetwork.zipline_subnet.name}"
      }
    }
  }
}

resource "google_managed_kafka_topic" "chronon_ooc_responses" {
  cluster    = google_managed_kafka_cluster.zipline_kafka.cluster_id
  topic_id   = "chronon-ooc-responses"
  location   = var.region
  project    = data.google_project.zipline.project_id

  partition_count   = 3
  replication_factor = 3

  configs = {
    "cleanup.policy" = "delete"
    "retention.ms"   = "604800000" # 7 days
  }
}