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
        "tenant_id",
        "keyvault_name",
        "keyvault_identity_client_id",
        "workload_identity_client_id",
        "warehouse_container_name",
        "storage_account_name",
      ] : trimspace(tostring(try(var.azure[key], ""))) != ""
    ])
    error_message = "azure must include non-empty location, tenant_id, keyvault_name, keyvault_identity_client_id, workload_identity_client_id, warehouse_container_name, and storage_account_name."
  }
}

module "zipline_orchestration" {
  source = "../../modules/zipline-orchestration"

  orchestration    = var.orchestration
  provider_context = local.provider_context
}
