resource "google_storage_bucket" "zipline" {
  name     = "zipline-${var.name}"
  location = var.region
  uniform_bucket_level_access = true
}