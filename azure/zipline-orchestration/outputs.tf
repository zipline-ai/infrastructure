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
  value       = azurerm_storage_container.artifact.name
}

output "warehouse_container_name" {
  description = "Azure storage container used for the Zipline warehouse."
  value       = azurerm_storage_container.warehouse.name
}

output "logs_container_name" {
  description = "Azure storage container used for Zipline logs."
  value       = azurerm_storage_container.logs.name
}
