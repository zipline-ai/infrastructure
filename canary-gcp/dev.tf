resource "google_storage_bucket" "zipline_dev_bucket" {
  name                        = "zipline-warehouse-dev"
  location                    = var.region
  uniform_bucket_level_access = true
}

resource "google_bigtable_table" "dev_table_partitions" {
  instance_name = module.base_setup.bigtable_instance_name
  name          = "TABLE_PARTITIONS_DEV"
  column_family {
    family = "cf"
  }
}

resource "google_bigtable_gc_policy" "dev_table_partitions_gc_policy" {
  instance_name = module.base_setup.bigtable_instance_name
  table         = google_bigtable_table.dev_table_partitions.name
  column_family = "cf"

  max_age {
    duration = "120h"
  }
}

resource "google_bigtable_table" "dev_gke_table_partitions" {
  instance_name = module.base_setup.bigtable_instance_name
  name          = "TABLE_PARTITIONS_DEV_GKE"
  column_family {
    family = "cf"
  }
}

resource "google_bigtable_gc_policy" "dev_gke_table_partitions_gc_policy" {
  instance_name = module.base_setup.bigtable_instance_name
  table         = google_bigtable_table.dev_gke_table_partitions.name
  column_family = "cf"

  max_age {
    duration = "120h"
  }
}