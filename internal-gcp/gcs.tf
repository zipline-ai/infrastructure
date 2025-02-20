resource "google_storage_bucket" "artifacts" {
  for_each                    = var.customer_accts
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
}

data "google_storage_bucket" "base_artifacts" {
  name = "zipline-artifacts-base"
}

data "google_project" "internal_project" {
}

resource "google_storage_transfer_job" "artifacts-transfer" {
  for_each    = var.customer_accts
  description = "Transfer artifacts to ${each.key}"
  project     = data.google_project.internal_project.project_id
  schedule {
    schedule_start_date {
      year  = formatdate("YYYY", timestamp())
      month = formatdate("MM", timestamp())
      day   = formatdate("DD", timestamp())
    }
    schedule_end_date {
      year  = formatdate("YYYY", timestamp())
      month = formatdate("MM", timestamp())
      day   = formatdate("DD", timestamp())
    }
  }
  transfer_spec {
    gcs_data_source {
      bucket_name = data.google_storage_bucket.base_artifacts.name
    }
    gcs_data_sink {
      bucket_name = google_storage_bucket.artifacts[each.key].name
    }
    transfer_options {
      delete_objects_unique_in_sink             = false
      delete_objects_from_source_after_transfer = false
    }
  }
  lifecycle {
    ignore_changes = [
      schedule,
    ]
  }
}