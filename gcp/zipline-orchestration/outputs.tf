output "network" {
  description = "VPC used by the cluster (created when gcp.network is omitted)."
  value       = local.network_name
}

output "subnet" {
  description = "Subnetwork used by the cluster."
  value       = local.subnet_name
}

output "network_created" {
  description = "Whether Terraform provisioned the VPC/subnet for this install."
  value       = local.create_network
}

output "gke_cluster_name" {
  description = "GKE cluster name."
  value       = google_container_cluster.main.name
}

output "gke_cluster_endpoint" {
  description = "GKE cluster API endpoint."
  value       = google_container_cluster.main.endpoint
  sensitive   = true
}

output "kubeconfig_command" {
  description = "Command to configure kubectl for this cluster."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.main.name} --region ${local.cloud_args.region} --project ${local.cloud_args.project_id}"
}

output "cloudsql_connection_name" {
  description = "Cloud SQL instance connection name (project:region:instance)."
  value       = google_sql_database_instance.zipline.connection_name
}

output "cloudsql_private_ip" {
  description = "Cloud SQL private IP."
  value       = google_sql_database_instance.zipline.private_ip_address
}

output "db_credentials_secret_id" {
  description = "Secret Manager id for database credentials."
  value       = google_secret_manager_secret.db_credentials.id
}

output "warehouse_bucket" {
  description = "GCS bucket used for the Zipline warehouse."
  value       = google_storage_bucket.warehouse.name
}

output "artifact_bucket" {
  description = "GCS bucket used for Zipline artifacts."
  value       = google_storage_bucket.artifact.name
}

output "logs_bucket" {
  description = "GCS bucket used for Zipline logs."
  value       = google_storage_bucket.logs.name
}

output "spark_libs_bucket" {
  description = "GCS bucket used for Flink/Spark jars."
  value       = local.spark_libs_bucket_name
}

output "bigtable_instance" {
  description = "Bigtable instance id."
  value       = google_bigtable_instance.zipline.name
}

output "orchestration_gsa_email" {
  description = "GSA email used by orchestration (hub, ui, eval) via Workload Identity."
  value       = google_service_account.orchestration.email
}

output "spark_gsa_email" {
  description = "GSA email used by Spark compute pods via Workload Identity."
  value       = google_service_account.spark.email
}

output "flink_gsa_email" {
  description = "GSA email used by Flink compute pods via Workload Identity."
  value       = google_service_account.flink.email
}

output "polaris_gsa_email" {
  description = "GSA email used by Polaris credential vending."
  value       = google_service_account.polaris_storage.email
}

output "ingress_load_balancer_ip" {
  description = "Reserved external IP used by the ingress-nginx-ui Service."
  value       = local.ingress_lb_ip
}

output "ingress_load_balancer_target" {
  description = "Provider-neutral DNS target for the public ingress controller."
  value       = module.zipline_orchestration.ingress_load_balancer_target
}
