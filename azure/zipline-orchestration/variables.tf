variable "orchestration" {
  description = "Shared Zipline orchestration install inputs consumed by modules/zipline-orchestration."
  type        = any
}

variable "subscription_id" {
  description = "Azure subscription ID."
  type        = string
}

variable "aks_resource_group" {
  description = "Resource group containing the AKS cluster."
  type        = string
}

variable "aks_cluster_name" {
  description = "AKS cluster name."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "tenant_id" {
  description = "Azure tenant ID."
  type        = string
}

variable "secrets_enabled" {
  description = "Whether the chart renders a SecretProviderClass and mounts the Secrets Store CSI volume."
  type        = bool
  default     = true
}

variable "database_password_secret_name" {
  description = "Key Vault secret name containing the Postgres password."
  type        = string
  default     = "pg-admin-password"
}

variable "database_username_secret_name" {
  description = "Key Vault secret name containing the Postgres username."
  type        = string
  default     = "pg-admin-username"
}

variable "keyvault_name" {
  description = "Azure Key Vault name used by the SecretProviderClass."
  type        = string
}

variable "keyvault_identity_client_id" {
  description = "User-assigned identity client ID used by the Key Vault CSI provider."
  type        = string
}

variable "workload_identity_client_id" {
  description = "User-assigned identity client ID annotated on the orchestration service account."
  type        = string
}

variable "compute_workload_identity_client_id" {
  description = "User-assigned identity client ID annotated on compute service accounts. Defaults to workload_identity_client_id."
  type        = string
  default     = ""
}

variable "warehouse_container_name" {
  description = "Warehouse storage container name only, without a URI scheme."
  type        = string

  validation {
    condition     = !strcontains(var.warehouse_container_name, "://")
    error_message = "warehouse_container_name must be a container name only, not a URI."
  }
}

variable "azure_storage_account_name" {
  description = "Azure Storage account backing warehouse and event logs."
  type        = string
}

variable "storage_path_prefix" {
  description = "Optional path prefix inside the warehouse container."
  type        = string
  default     = ""
}

variable "ingress_load_balancer_ip" {
  description = "Static Azure public IP for the shared ingress-nginx Service."
  type        = string
  default     = ""
}

variable "load_balancer_resource_group" {
  description = "AKS node resource group containing static public IPs."
  type        = string
  default     = ""
}

variable "warehouse_prefix" {
  description = "Warehouse URI passed to Azure Crucible runtime. Defaults to the ABFS warehouse path."
  type        = string
  default     = ""
}

variable "flink_state_uri" {
  description = "Flink state URI passed to Azure Crucible runtime. Defaults to the ABFS flink-state path."
  type        = string
  default     = ""
}

variable "kv_store_type" {
  description = "Azure KV store type passed to Hub."
  type        = string
  default     = "cosmos"
}

variable "table_partitions_dataset" {
  description = "KV table partitions dataset/table name."
  type        = string
  default     = "TABLE_PARTITIONS"
}

variable "data_quality_metrics_dataset" {
  description = "KV data quality metrics dataset/table name."
  type        = string
  default     = "DATA_QUALITY_METRICS"
}

variable "chronon_online_class" {
  description = "Chronon online class used by Azure Crucible runtime."
  type        = string
  default     = "ai.chronon.integrations.cloud_azure.AzureApiImpl"
}

variable "crucible_jar_name" {
  description = "Azure Crucible jar name."
  type        = string
  default     = "cloud_azure_lib_deploy.jar"
}

variable "crucible_jar_uri" {
  description = "Optional Azure Crucible jar URI."
  type        = string
  default     = ""
}

variable "crucible_spot_executors" {
  description = "Whether Azure Crucible should request spot executors."
  type        = bool
  default     = true
}

variable "ingress_service_annotations" {
  description = "Extra annotations applied to ingress-nginx controller Services."
  type        = map(string)
  default     = {}
}

variable "extra_keyvault_secret_names" {
  description = "Additional Key Vault secret names mounted by the SecretProviderClass."
  type        = list(string)
  default     = []
}
