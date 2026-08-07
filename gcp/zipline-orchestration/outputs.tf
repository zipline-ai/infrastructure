output "ingress_load_balancer_hostname" {
  description = "Load balancer hostname for the public ingress controller."
  value       = module.zipline_orchestration.ingress_load_balancer_hostname
}

output "ingress_load_balancer_ip" {
  description = "Load balancer IP for the public ingress controller."
  value       = module.zipline_orchestration.ingress_load_balancer_ip
}

output "ingress_load_balancer_target" {
  description = "Provider-neutral DNS target for the public ingress controller."
  value       = module.zipline_orchestration.ingress_load_balancer_target
}

output "project_id" {
  description = "GCP project containing the deployment."
  value       = local.project_id
}

output "gke_cluster_name" {
  description = "GKE cluster name."
  value       = google_container_cluster.main.name
}

output "gke_cluster_location" {
  description = "GKE cluster region."
  value       = google_container_cluster.main.location
}

output "network_self_link" {
  description = "VPC network used by GKE and Cloud SQL."
  value       = local.network_self_link
}

output "artifact_bucket_name" {
  description = "GCS bucket used for Zipline artifacts."
  value       = google_storage_bucket.this[local.artifact_bucket_name].name
}

output "warehouse_bucket_name" {
  description = "GCS bucket used for the Zipline warehouse."
  value       = google_storage_bucket.this[local.warehouse_bucket_name].name
}

output "logs_bucket_name" {
  description = "GCS bucket used for Zipline logs."
  value       = google_storage_bucket.this[local.logs_bucket_name].name
}

output "postgres_private_ip" {
  description = "Private IP address of the Cloud SQL PostgreSQL instance."
  value       = google_sql_database_instance.main.private_ip_address
}

output "workload_service_account_emails" {
  description = "Google service accounts used through GKE Workload Identity."
  value = {
    for key, account in google_service_account.workload : key => account.email
  }
}

output "gke_node_service_account_email" {
  description = "Least-privilege Google service account used by GKE nodes."
  value       = google_service_account.gke_nodes.email
}

output "prometheus_query_endpoint" {
  description = "Managed Service for Prometheus query API endpoint."
  value       = local.prometheus_query_endpoint
}
