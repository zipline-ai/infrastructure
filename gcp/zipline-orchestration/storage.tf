locals {
  storage_buckets = toset([
    local.artifact_bucket_name,
    local.warehouse_bucket_name,
    local.logs_bucket_name,
  ])

  storage_bucket_grants = {
    artifacts = {
      bucket = local.artifact_bucket_name
      role   = "roles/storage.objectViewer"
    }
    warehouse = {
      bucket = local.warehouse_bucket_name
      role   = "roles/storage.objectAdmin"
    }
    logs = {
      bucket = local.logs_bucket_name
      role   = "roles/storage.objectCreator"
    }
  }

  storage_bucket_workloads = {
    for item in flatten([
      for grant_name, grant in local.storage_bucket_grants : [
        for workload in keys(local.workload_service_accounts) : {
          key      = "${grant_name}:${workload}"
          bucket   = grant.bucket
          role     = grant.role
          workload = workload
        }
      ]
    ]) : item.key => item
  }
}

resource "google_storage_bucket_iam_member" "workload" {
  for_each = local.storage_bucket_workloads

  bucket = google_storage_bucket.this[each.value.bucket].name
  role   = each.value.role
  member = "serviceAccount:${google_service_account.workload[each.value.workload].email}"
}

resource "google_storage_bucket" "this" {
  for_each = local.storage_buckets

  project                     = local.project_id
  name                        = each.value
  location                    = local.bucket_location
  uniform_bucket_level_access = true
  force_destroy               = local.cloud_args.bucket_force_destroy

  versioning {
    enabled = local.cloud_args.bucket_versioning_enabled
  }

  depends_on = [google_project_service.required]
}
