module "base_setup" {
  source = "../base-gcp"

  customer_name = "canary"

  artifact_prefix = "gs://zipline-canary-artifacts"
  zipline_version = "latest"
  table_partitions_dataset = google_bigtable_table.table_partitions_ci.name
}