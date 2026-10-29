resource "google_bigtable_instance" "zipline" {
  name                = local.bigtable_instance_name
  deletion_protection = local.cloud_args.bigtable_deletion_protection

  cluster {
    cluster_id   = "${local.bigtable_instance_name}-c1"
    zone         = local.bigtable_zone
    storage_type = "SSD"

    autoscaling_config {
      min_nodes      = local.cloud_args.bigtable_min_nodes
      max_nodes      = local.cloud_args.bigtable_max_nodes
      cpu_target     = local.cloud_args.bigtable_cpu_target
      storage_target = local.cloud_args.bigtable_storage_target_gib
    }

    kms_key_name = local.cloud_args.cmek_key_id != "" ? local.cloud_args.cmek_key_id : null
  }
}

# §9.2: GROUPBY_INGEST is hardcoded in BigQuery external-table DDL
# (BigTableKVStoreImpl.scala:508). Create it explicitly — batch ingest otherwise
# breaks in a way that only shows up in BQ queries (R3).
resource "google_bigtable_app_profile" "groupby_ingest" {
  instance       = google_bigtable_instance.zipline.name
  app_profile_id = "GROUPBY_INGEST"
  description    = "App profile for group-by batch ingest routed through BigQuery external tables."

  single_cluster_routing {
    cluster_id                 = "${local.bigtable_instance_name}-c1"
    allow_transactional_writes = true
  }

  ignore_warnings = true
}

# ---------------------------------------------------------------------------
# Pre-created KV + metadata tables.
#
# The chronon spark/flink GSAs run with roles/bigtable.user — which includes
# tables.get/mutateRows/readRows but NOT tables.create. The client-side
# "create on demand" pattern that the plan doc §9.2 references would require
# bigtable.admin on every executor, which is a wider surface than we want.
# Mirroring infra-gcp-prod's base-gcp/bigtable.tf: pre-create the fixed-name
# tables + GC policies at infra-apply time, same shape (cf column family,
# 120h max_age, 10000 max_version for KV-shaped tables).
#
# Dataset-named batch tables (not these fixed-name ones) still land on the
# executor; those need bigtable.admin elsewhere or will fail. Phase 2+ owner.
# ---------------------------------------------------------------------------

locals {
  bigtable_kv_tables = {
    GROUPBY_BATCH                  = { max_age_hours = 120, max_versions = 10000 }
    GROUPBY_STREAMING              = { max_age_hours = 120, max_versions = 10000 }
    TILE_SUMMARIES                 = { max_age_hours = 120, max_versions = 10000 }
    CHRONON_METADATA               = { max_age_hours = 120, max_versions = 10000 }
    DATA_QUALITY_METRICS_BATCH     = { max_age_hours = 120, max_versions = 10000 }
    DATA_QUALITY_METRICS_STREAMING = { max_age_hours = 120, max_versions = 10000 }
  }
}

resource "google_bigtable_table" "kv" {
  for_each = local.bigtable_kv_tables

  instance_name = google_bigtable_instance.zipline.name
  name          = each.key

  column_family {
    family = "cf"
  }
}

resource "google_bigtable_gc_policy" "kv" {
  for_each = local.bigtable_kv_tables

  instance_name = google_bigtable_instance.zipline.name
  table         = google_bigtable_table.kv[each.key].name
  column_family = "cf"

  mode = "UNION"
  max_age {
    duration = "${each.value.max_age_hours}h"
  }
  max_version {
    number = each.value.max_versions
  }
}

# TABLE_PARTITIONS has a slightly different legacy shape: no mode (default
# INTERSECTION), max_age only, no max_version. Keep that intentional
# divergence rather than normalizing it.
resource "google_bigtable_table" "table_partitions" {
  instance_name = google_bigtable_instance.zipline.name
  name          = "TABLE_PARTITIONS"

  column_family {
    family = "cf"
  }
}

resource "google_bigtable_gc_policy" "table_partitions" {
  instance_name = google_bigtable_instance.zipline.name
  table         = google_bigtable_table.table_partitions.name
  column_family = "cf"

  max_age {
    duration = "120h"
  }
}
