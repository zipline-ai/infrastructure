
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

module "dev_orch" {
  source = "../orchestration-gcp"

  zipline_version = "latest"

  name_prefix     = "dev"
  region          = var.region
  personnel_email = var.personnel_email
  alerting_email  = var.personnel_email

  zipline_ui_domain = var.dev_zipline_ui_domain
  hub_domain        = var.dev_hub_domain

  artifact_prefix              = "gs://zipline-artifacts-dev"
  bigtable_instance_name       = module.base_setup.bigtable_instance_name
  logs_bucket_name             = module.base_setup.logs_bucket_name
  table_partitions_dataset     = google_bigtable_table.dev_table_partitions.name
  data_quality_metrics_dataset = google_bigtable_table.dev_data_quality_metrics.name
  dataproc_service_account     = module.base_setup.dataproc_service_account_id

  vpc_id      = google_compute_network.zipline_vpc.id
  vpc_name    = google_compute_network.zipline_vpc.name
  subnet_name = google_compute_subnetwork.zipline_subnet.name
}