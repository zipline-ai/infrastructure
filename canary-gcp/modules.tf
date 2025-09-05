module "base_setup" {
  source = "../base-gcp"

  customer_name = "canary"

  artifact_prefix = "gs://zipline-canary-artifacts"
  zipline_version = "latest"
  table_partitions_dataset = google_bigtable_table.table_partitions_ci.name
  hub_domain = "canary-gke-orch.zipline.ai"
  temporal_domain = "canary-gke-temporal.zipline.ai"
  zipline_ui_domain = "canary-gke.zipline.ai"
}