resource "google_storage_bucket" "zipline" {
  for_each = var.customer_names
  name     = "zipline-artifacts-${lower(each.value)}"
  location = var.region
  uniform_bucket_level_access = true
}

resource "google_storage_bucket_iam_member" "zipline-bucket-binding" {
  for_each = var.customer_names
  bucket   = google_storage_bucket.zipline[each.key].name
  role     = "roles/storage.objectAdmin"
  member   = "group:${var.personnel_email}"
}