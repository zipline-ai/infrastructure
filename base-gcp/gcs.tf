resource "google_storage_bucket" "zipline" {
  name     = "zipline"
  location = var.region
  uniform_bucket_level_access = true
}