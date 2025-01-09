resource "google_storage_bucket" "zipline" {
  count    = var.create_warehouse_bucket ? 1 : 0  
  name     = "zipline-warehouse-${lower(var.customer_name)}"
  location = var.region
  uniform_bucket_level_access = true
}

# only expecting canary to be created
resource "google_storage_bucket" "zipline_artifacts_bucket" {
  name     = "zipline-artifacts-${lower(var.customer_name)}"
  location = var.region
  uniform_bucket_level_access = true
}