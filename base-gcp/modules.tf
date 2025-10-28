module "orchestration" {
  source = "../orchestration-gcp"

  project_id = data.google_project.zipline.project_id
  zipline_version = var.zipline_version

  name_prefix     = var.customer_name
  region          = var.region
  personnel_email = var.personnel_email
  alerting_email  = var.alerting_email

  zipline_ui_domain = var.zipline_ui_domain
  hub_domain        = var.hub_domain

  artifact_prefix              = var.artifact_prefix
  bigtable_instance_name       = google_bigtable_instance.zipline_bigtable_instance.name
  logs_bucket_name             = google_storage_bucket.zipline-logs.name
  table_partitions_dataset     = var.table_partitions_dataset
  data_quality_metrics_dataset = var.data_quality_metrics_dataset
  dataproc_service_account     = google_service_account.dataproc_sa.id

  vpc_id      = var.vpc_network_id != "" ? var.vpc_network_id : google_compute_network.zipline_vpc[0].id
  vpc_name    = var.vpc_network_name != "" ? var.vpc_network_name : google_compute_network.zipline_vpc[0].name
  subnet_name = var.vpc_subnet_name != "" ? var.vpc_subnet_name : google_compute_subnetwork.zipline_subnet[0].name
}

output "docker_hub_remote_repository_id" {
  value = module.orchestration.docker_hub_remote_repository_id
}

output "orchestration_service_name" {
  value = module.orchestration.orchestration_service_name
}

output "orchestration_service_account_id" {
  value = module.orchestration.orchestration_service_account_id
}