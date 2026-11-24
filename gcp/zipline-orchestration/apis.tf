# A new project starts with most of these APIs off, and the first apply fails
# until they are on. Set gcp.enable_apis = false when the deploying identity
# can't call serviceusage (APIs managed by a platform team).
locals {
  required_apis = [
    "bigquery.googleapis.com",
    "bigquerystorage.googleapis.com",
    "bigtable.googleapis.com",
    "bigtableadmin.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "pubsub.googleapis.com",
    "secretmanager.googleapis.com",
    "servicenetworking.googleapis.com",
    "sqladmin.googleapis.com",
    "sts.googleapis.com",
  ]
}

resource "google_project_service" "required" {
  for_each = local.cloud_args.enable_apis ? toset(local.required_apis) : toset([])

  project = local.cloud_args.project_id
  service = each.value

  # Other workloads in the project may use these APIs; leave them on at teardown.
  disable_on_destroy         = false
  disable_dependent_services = false
}
