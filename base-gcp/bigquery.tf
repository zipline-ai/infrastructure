resource "google_bigquery_reservation" "zipline_reservation" {
  project = data.google_project.zipline.project_id
  location = "US"
  name = "bq-bt-uploads"
  slot_capacity = 0
  autoscale {
    max_slots = 50
  }
}

resource "google_bigquery_reservation_assignment" "query_assignment" {
  assignee    = "projects/${data.google_project.zipline.project_id}"
  job_type    = "QUERY"
  reservation = google_bigquery_reservation.zipline_reservation.name
}

resource "google_dataproc_metastore_service" "big_query_metastore" {
  location = "us-central1"
  service_id = "zipline-metadata-service"

  hive_metastore_config {
    version = "3.1.2"
    endpoint_protocol = "GRPC"
  }
}

resource "google_dataproc_metastore_federation" "big_query_metastore_federation" {
  location      = "us-central1"
  federation_id = "zipline-metastore-fed"
  version       = "3.1.2"

  backend_metastores {
    rank           = "1"
    name           = data.google_project.zipline.id
    metastore_type = "BIGQUERY"
  }

  backend_metastores {
    rank           = "0"
    name           = google_dataproc_metastore_service.big_query_metastore.id
    metastore_type = "DATAPROC_METASTORE"
  }
}
