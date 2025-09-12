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

// Grant access to the service accounts to read from artifacts bucket
locals {
  # Flatten the map into a list of objects for easier use
  customer_service_accts = flatten([
    for customer, accts in var.service_accts : [
      for acct in accts : {
        customer = customer
        acct = acct
      }
    ]
  ])
}

resource "google_storage_bucket_iam_member" "service-acct-bucket-binding" {
  for_each = { for service_acct in local.customer_service_accts :
    "${service_acct.customer}:${service_acct.acct}" => {
      customer = service_acct.customer
      acct     = service_acct.acct
    }
  }
  bucket = google_storage_bucket.artifacts[each.value.customer].name
  member = "serviceAccount:${each.value.acct}"
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

resource "google_storage_bucket" "spark_libs" {
  name                        = "zipline-spark-libs"
  location                    = var.region
  uniform_bucket_level_access = true
}

# Grant access to spark_libs bucket
resource "google_storage_bucket_iam_member" "dataproc-spark-libs-binding" {
  for_each = var.customer_projects
  bucket   = google_storage_bucket.spark_libs.name
  role     = "roles/storage.objectViewer"
  member   = "serviceAccount:dataproc@${each.value}.iam.gserviceaccount.com"

  depends_on = [
    google_storage_bucket.spark_libs
  ]
}

# Make all objects in the bucket publicly readable
resource "google_storage_bucket_iam_member" "spark_libs_public_access" {
  bucket = google_storage_bucket.spark_libs.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}
