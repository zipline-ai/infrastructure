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

resource "google_bigtable_table" "dev_data_quality_metrics" {
  instance_name = module.base_setup.bigtable_instance_name
  name          = "DATA_QUALITY_METRICS_DEV"
  column_family {
    family = "cf"
  }
}

resource "google_bigtable_gc_policy" "dev_data_quality_metrics_gc_policy" {
  instance_name = module.base_setup.bigtable_instance_name
  table         = google_bigtable_table.dev_data_quality_metrics.name
  column_family = "cf"

  max_age {
    duration = "120h"
  }
}

resource "google_bigtable_table" "table_partitions_ci" {
  instance_name = module.base_setup.bigtable_instance_name
  name          = "TABLE_PARTITIONS_CI"
  column_family {
    family = "cf"
  }
}

resource "google_bigtable_gc_policy" "table_partitions_ci_gc_policy" {
  instance_name = module.base_setup.bigtable_instance_name
  table         = google_bigtable_table.table_partitions_ci.name
  column_family = "cf"

  max_age {
    duration = "120h"
  }
}

resource "google_bigtable_table" "data_quality_metrics_ci" {
  instance_name = module.base_setup.bigtable_instance_name
  name          = "DATA_QUALITY_METRICS_CI"
  column_family {
    family = "cf"
  }
}

resource "google_bigtable_gc_policy" "data_quality_metrics_ci_gc_policy" {
  instance_name = module.base_setup.bigtable_instance_name
  table         = google_bigtable_table.data_quality_metrics_ci.name
  column_family = "cf"

  max_age {
    duration = "120h"
  }
}
