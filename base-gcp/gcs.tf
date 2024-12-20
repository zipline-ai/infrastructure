resource "google_storage_bucket" "warehouse" {
  name     = "zl-warehouse"
  location = var.region
  uniform_bucket_level_access = true
}

resource "google_storage_bucket" "jars" {
  name     = "zl-jars"
  location = var.region
  uniform_bucket_level_access = true
}