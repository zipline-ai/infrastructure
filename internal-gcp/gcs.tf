resource "google_storage_bucket" "artifacts" {
  for_each = var.customer_accts
  name     = "zipline-artifacts-${lower(each.key)}"
  location = var.region
  uniform_bucket_level_access = true
}

resource "google_storage_bucket_iam_member" "personnel-artifacts-bucket-binding" {
  for_each = var.customer_accts
  bucket   = google_storage_bucket.artifacts[each.key].name
  role     = "roles/storage.objectViewer"
  member   = "group:${each.value}"
}

resource "google_storage_bucket_iam_member" "dataproc-bucket-binding" {
  for_each = var.customer_projects
  bucket   = google_storage_bucket.artifacts[each.key].name
  role     = "roles/storage.objectViewer"
  member   = "serviceAccount:dataproc@${each.value}.iam.gserviceaccount.com"
}