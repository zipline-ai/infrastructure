resource "google_storage_bucket" "artifacts" {
  for_each                    = var.customer_projects
  name                        = "zipline-artifacts-${lower(each.key)}"
  location                    = var.region
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

  depends_on = [
    google_storage_bucket.artifacts
  ]
}

resource "google_storage_bucket_iam_member" "airflow-bucket-binding" {
  bucket = google_storage_bucket.artifacts["etsy"].name
  member = "serviceAccount:gke-mirror-sa-airflow@etsy-batchjobs-prod.iam.gserviceaccount.com"
  role   = "roles/storage.objectViewer"
}

resource "google_storage_bucket_iam_member" "buildkite-bucket-binding" {
  bucket = google_storage_bucket.artifacts["etsy"].name
  member = "serviceAccount:buildkite-default@etsy-buildkite-prod.iam.gserviceaccount.com"
  role   = "roles/storage.objectViewer"
}


resource "google_storage_bucket_iam_member" "github-bucket-binding" {
  for_each = var.customer_projects
  bucket   = google_storage_bucket.artifacts[each.key].name
  role     = "roles/storage.objectUser"
  member   = "serviceAccount:${google_service_account.github.email}"
  depends_on = [
    google_storage_bucket.artifacts
  ]
}


resource "google_storage_bucket" "base_artifacts" {
  name                        = "zipline-artifacts-base"
  location                    = var.region
  uniform_bucket_level_access = true
}


resource "google_storage_bucket_iam_member" "github-base-bucket-binding" {
  bucket = google_storage_bucket.base_artifacts.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.github.email}"
}

resource "google_service_account" "logs-viewer" {
  account_id   = "logs-viewer"
  display_name = "Logs Viewer"
  lifecycle {
    prevent_destroy = true
  }
}