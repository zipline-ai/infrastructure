
module "base_setup" {
  source = "../base-gcp"

  customer_name = "canary"

  artifact_prefix              = "gs://zipline-artifacts-canary"
  zipline_version              = "latest"
  table_partitions_dataset     = google_bigtable_table.table_partitions_ci.name
  data_quality_metrics_dataset = var.data_quality_metrics_ci_dataset
  hub_domain                   = var.hub_domain
  zipline_ui_domain            = var.zipline_ui_domain
}