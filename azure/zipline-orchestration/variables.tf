variable "namespace" {
  description = "Namespace where Zipline orchestration is installed."
  type        = string
  default     = "zipline-system"
}

variable "release_name" {
  description = "Helm release name for the Zipline orchestration chart."
  type        = string
  default     = "zipline-orchestration"
}

variable "namespace_labels" {
  description = "Labels applied to the orchestration namespace."
  type        = map(string)
  default     = {}
}

variable "namespace_annotations" {
  description = "Annotations applied to the orchestration namespace."
  type        = map(string)
  default     = {}
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

variable "helm_wait" {
  description = "Whether Helm waits for all resources to become ready."
  type        = bool
  default     = true
}

variable "helm_timeout" {
  description = "Helm operation timeout in seconds."
  type        = number
  default     = 300
}

variable "customer_name" {
  description = "Zipline customer/environment name."
  type        = string
}

variable "artifact_prefix" {
  description = "Artifact prefix passed to Zipline services."
  type        = string
}

variable "zipline_version" {
  description = "Zipline image tag."
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

variable "database_host" {
  description = "Postgres host for Zipline orchestration."
  type        = string
}

variable "database_port" {
  description = "Postgres port."
  type        = number
  default     = 5432
}

variable "database_name" {
  description = "Postgres database name for Zipline orchestration."
  type        = string
  default     = "execution_info"
}

variable "database_ssl_mode" {
  description = "Optional Postgres sslmode."
  type        = string
  default     = "require"
}

variable "database_credentials_secret_name" {
  description = "Kubernetes secret containing database credentials."
  type        = string
  default     = "db-credentials"
}

variable "database_username_secret_key" {
  description = "Secret key containing the database username."
  type        = string
  default     = "username"
}

variable "database_password_secret_key" {
  description = "Secret key containing the database password."
  type        = string
  default     = "password"
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

variable "domain" {
  description = "Unified public hostname for Zipline. Services are exposed under paths on this host."
  type        = string
}

variable "tls_secret_name" {
  description = "Kubernetes TLS secret for the unified public hostname. Leave empty to render no TLS blocks."
  type        = string
  default     = "zipline-tls-secret"
}

variable "cert_manager_cluster_issuer" {
  description = "Optional cert-manager cluster issuer annotation for application ingresses."
  type        = string
  default     = "letsencrypt-prod"
}

variable "ingress_class_name" {
  description = "IngressClass used by all Zipline application ingresses."
  type        = string
  default     = "nginx-ui"
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

variable "deploy_fetcher" {
  description = "Whether to deploy the fetcher service and ingress."
  type        = bool
  default     = false
}

variable "spark_image" {
  description = "Spark image repository and tag used by Crucible."
  type        = string
  default     = "ziplineai/spark:nightly"
}

variable "flink_image" {
  description = "Flink image repository and tag used by Crucible."
  type        = string
  default     = "ziplineai/flink:1.20.3"
}

variable "spark_service_account_name" {
  description = "Service account used by Spark driver pods."
  type        = string
  default     = "spark-operator-spark"
}

variable "flink_service_account_name" {
  description = "Service account used by Flink jobs."
  type        = string
  default     = "flink"
}

variable "compute_default_namespace" {
  description = "Default namespace for Crucible compute jobs."
  type        = string
  default     = "zipline-default"
}

variable "compute_namespaces" {
  description = "Compute namespaces bootstrapped by the chart."
  type        = any
  default = [
    {
      name = "zipline-default"
      team = "default"
    }
  ]
}

variable "spark_event_log_dir" {
  description = "Spark event log directory. Defaults to abfss://<warehouse_container>@<storage_account>.dfs.core.windows.net/<prefix>/spark-events."
  type        = string
  default     = ""
}

variable "spark_history_extra_spark_opts" {
  description = "Additional Spark History Server JVM/Spark options."
  type        = list(string)
  default     = []
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

variable "compute_rbac_create" {
  description = "Whether the chart creates compute namespace RBAC."
  type        = bool
  default     = true
}

variable "compute_image_prepull_enabled" {
  description = "Whether the chart should prepull compute images."
  type        = bool
  default     = true
}

variable "prometheus_query_endpoint" {
  description = "Prometheus query endpoint for the UI."
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

variable "auth" {
  description = "Chart auth values object. Secrets are read through Key Vault."
  type        = any
  default = {
    enabled = false
  }
}

variable "runtime_env" {
  description = "Additional env vars passed to all orchestration services."
  type        = any
  default     = []
}

variable "hub_env" {
  description = "Additional env vars passed only to Hub."
  type        = any
  default     = []
}

variable "image_pull_secret_name" {
  description = "Existing image pull secret name when create_image_pull_secret is false."
  type        = string
  default     = ""
}

variable "create_image_pull_secret" {
  description = "Create a Docker Hub image pull secret in the orchestration namespace."
  type        = bool
  default     = false
}

variable "dockerhub_username" {
  description = "Docker Hub username for the generated pull secret."
  type        = string
  default     = "ziplineai"
}

variable "dockerhub_token" {
  description = "Docker Hub token for the generated pull secret."
  type        = string
  default     = ""
  sensitive   = true
}

variable "install_secrets_store_csi_driver" {
  description = "Install the Secrets Store CSI driver. Disable this when using the AKS Key Vault CSI add-on."
  type        = bool
  default     = false
}

variable "install_cert_manager" {
  description = "Install cert-manager."
  type        = bool
  default     = true
}

variable "install_flink_operator" {
  description = "Install the Flink Kubernetes operator."
  type        = bool
  default     = true
}

variable "install_opentelemetry_operator" {
  description = "Install the OpenTelemetry operator."
  type        = bool
  default     = false
}

variable "ingress_service_annotations" {
  description = "Extra annotations applied to every ingress-nginx controller Service."
  type        = map(string)
  default     = {}
}

variable "ingress_annotations" {
  description = "Extra annotations applied to every application Ingress."
  type        = map(string)
  default     = {}
}

variable "extra_secret_objects" {
  description = "Additional SecretProviderClass secretObjects entries."
  type        = any
  default     = []
}

variable "extra_keyvault_secret_names" {
  description = "Additional Key Vault secret names mounted by the SecretProviderClass."
  type        = list(string)
  default     = []
}

variable "extra_values" {
  description = "Additional Helm values objects merged after the wrapper-generated values."
  type        = list(any)
  default     = []
}

variable "extra_values_yaml" {
  description = "Additional raw Helm values YAML merged after the wrapper-generated values."
  type        = list(string)
  default     = []
}
