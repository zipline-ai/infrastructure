resource "google_storage_bucket" "zipline_dev_bucket" {
  name                        = "zipline-warehouse-dev"
  location                    = var.region
  uniform_bucket_level_access = true
}