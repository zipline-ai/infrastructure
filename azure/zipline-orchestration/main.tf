variable "orchestration" {
  description = "Shared Zipline orchestration install inputs consumed by modules/zipline-orchestration."
  type        = any

  validation {
    condition     = can(regex("^(abfss|wasbs)://[^@/]+@[^/]+/.+", trimspace(try(var.orchestration.deployment.artifact_prefix, ""))))
    error_message = "orchestration.deployment.artifact_prefix must be an ABFS/WASBS URI such as abfss://artifacts@example.dfs.core.windows.net/zipline/artifacts."
  }
}

variable "azure" {
  description = "Azure-specific orchestration wrapper inputs."
  type        = any

  validation {
    condition = alltrue([
      for key in [
        "location",
        "warehouse_container_name",
        "storage_account_name",
      ] : trimspace(tostring(try(var.azure[key], ""))) != ""
    ])
    error_message = "azure must include non-empty location, warehouse_container_name, and storage_account_name."
  }
}

module "zipline_orchestration" {
  source = "../../modules/zipline-orchestration"

  orchestration    = var.orchestration
  provider_context = local.provider_context

  depends_on = [
    azurerm_kubernetes_cluster_node_pool.user,
    azurerm_key_vault_secret.db_password,
    azurerm_key_vault_secret.db_username,
    azurerm_private_endpoint.postgres,
    azurerm_storage_data_lake_gen2_path.spark_events,
    azurerm_monitor_data_collection_rule_association.prometheus_endpoint,
    azurerm_monitor_data_collection_rule_association.prometheus_rule,
    azurerm_role_assignment.aks_monitoring_metrics_publisher,
    azurerm_role_assignment.workload_monitoring_reader,
    kubernetes_config_map_v1.ama_metrics_settings,
    azurerm_role_assignment.workload_keyvault_secrets_user,
    azurerm_role_assignment.workload_storage,
    azurerm_role_assignment.aks_acr_pull,
  ]
}
