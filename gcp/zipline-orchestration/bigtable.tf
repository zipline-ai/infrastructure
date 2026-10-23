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
      storage_target = local.cloud_args.bigtable_storage_target_gib * 1024 * 1024 * 1024
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
