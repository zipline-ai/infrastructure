module "base_setup" {
  source = "../base-gcp"

  customer_name = "canary"

  artifact_prefix = "gs://zipline-canary-artifacts"
  zipline_version = "64ed58f364b5951f3dff1dc27a7c3a66a07682cf"
  table_partitions_dataset = google_bigtable_table.table_partitions_ci.name
}