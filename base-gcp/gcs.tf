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