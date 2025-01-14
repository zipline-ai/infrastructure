resource "google_storage_bucket" "zipline" {
  name     = "zipline-warehouse-${lower(var.customer_name)}"
  location = var.region
  uniform_bucket_level_access = true
}