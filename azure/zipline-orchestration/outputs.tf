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

output "artifact_container_name" {
  description = "Azure storage container used for Zipline artifacts."
  value       = azurerm_storage_container.this[local.artifact_container_name].name
}

output "warehouse_container_name" {
  description = "Azure storage container used for the Zipline warehouse."
  value       = azurerm_storage_container.this[local.cloud_args.warehouse_container_name].name
}

output "logs_container_name" {
  description = "Azure storage container used for Zipline logs."
  value       = azurerm_storage_container.this[local.logs_container_name].name
}

output "resource_group_name" {
  description = "Azure resource group for the Crucible deployment."
  value       = azurerm_resource_group.main.name
}

output "aks_cluster_name" {
  description = "AKS cluster name."
  value       = azurerm_kubernetes_cluster.main.name
}

output "aks_oidc_issuer_url" {
  description = "AKS OIDC issuer URL used by workload identity federations."
  value       = azurerm_kubernetes_cluster.main.oidc_issuer_url
}

output "keyvault_name" {
  description = "Azure Key Vault used for orchestration secrets."
  value       = azurerm_key_vault.main.name
}

output "postgres_fqdn" {
  description = "Azure PostgreSQL FQDN used by Zipline orchestration."
  value       = azurerm_postgresql_flexible_server.main.fqdn
}

output "workload_identity_client_id" {
  description = "Azure workload identity client ID used by orchestration pods."
  value       = local.workload_identity_client_id
}

output "monitor_workspace_id" {
  description = "Azure Monitor workspace used for managed Prometheus metrics."
  value       = azurerm_monitor_workspace.prometheus.id
}

output "prometheus_query_endpoint" {
  description = "PromQL query endpoint passed to the Zipline UI."
  value       = azurerm_monitor_workspace.prometheus.query_endpoint
}
