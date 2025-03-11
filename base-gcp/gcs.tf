resource "google_storage_bucket" "zipline" {
  name                        = "zipline-warehouse-${lower(var.customer_name)}"
  location                    = var.region
  uniform_bucket_level_access = true
}

resource "google_storage_bucket_iam_member" "zipline-bucket-binding" {
  bucket = google_storage_bucket.zipline.name
  role   = "roles/storage.objectAdmin"
  member = "group:${var.personnel_email}"
}

resource "google_storage_bucket" "zipline-logs" {
  name                        = "zipline-logs-${lower(var.customer_name)}"
  location                    = var.region
  uniform_bucket_level_access = true
}

resource "google_storage_bucket_iam_member" "zipline-logs-bucket-binding" {
  bucket = "${google_storage_bucket.zipline-logs.name}"
  member = "serviceAccount:${var.control_plane_service_account}"
  role   = "roles/storage.objectViewer"
}