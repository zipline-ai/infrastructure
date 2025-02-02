resource "google_bigquery_reservation" "zipline_reservation" {
  project       = data.google_project.zipline.project_id
  location      = var.region
  name          = "bq-bt-uploads"
  slot_capacity = 0
  autoscale {
    max_slots = 50
  }
}

resource "google_bigquery_reservation_assignment" "query_assignment" {
  assignee    = "projects/${data.google_project.zipline.project_id}"
  job_type    = "QUERY"
  reservation = google_bigquery_reservation.zipline_reservation.id
  depends_on  = [google_bigquery_reservation.zipline_reservation]
}