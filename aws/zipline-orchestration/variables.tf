variable "namespace" {
  description = "Namespace where Zipline orchestration is installed."
  type        = string
  default     = "zipline-system"
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

variable "region" {
  description = "AWS region."
  type        = string
}

variable "aws_account_id" {
  description = "Optional AWS account ID guard for provider operations."
  type        = string
  default     = ""
}

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID used by the AWS Load Balancer Controller."
  type        = string
  default     = ""
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
  default     = ""
}

variable "database_jdbc_url" {
  description = "Optional explicit JDBC URL for orchestration services."
  type        = string
  default     = ""
}

variable "database_url" {
  description = "Optional explicit Postgres URL for services that use DATABASE_URL."
  type        = string
  default     = ""
}

variable "database_secret_arn" {
  description = "AWS Secrets Manager secret ARN containing password and username JSON fields."
  type        = string
}

variable "warehouse_bucket" {
  description = "Warehouse S3 bucket name only, without a URI scheme."
  type        = string

  validation {
    condition     = !strcontains(var.warehouse_bucket, "://")
    error_message = "warehouse_bucket must be a bucket name only, not a URI."
  }
}

variable "orchestration_role_arn" {
  description = "IAM role ARN annotated on the orchestration service account."
  type        = string
}

variable "spark_compute_role_arn" {
  description = "IAM role ARN annotated on Spark and Flink compute service accounts."
  type        = string
}

variable "flink_compute_role_arn" {
  description = "IAM role ARN annotated on Flink compute service accounts. Defaults to spark_compute_role_arn."
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
  default     = ""
}

variable "ingress_class_name" {
  description = "IngressClass used by all Zipline application ingresses."
  type        = string
  default     = "nginx-ui"
}

variable "cert_manager_cluster_issuer" {
  description = "Optional cert-manager cluster issuer annotation for application ingresses."
  type        = string
  default     = ""
}

variable "deploy_fetcher" {
  description = "Whether to deploy the fetcher service and ingress."
  type        = bool
  default     = false
}

variable "fetcher_replicas" {
  description = "Fetcher replica count."
  type        = number
  default     = 3
}

variable "hub_image" {
  description = "Hub image repository."
  type        = string
  default     = "ziplineai/hub-aws"
}

variable "eval_image" {
  description = "Eval image repository."
  type        = string
  default     = "ziplineai/eval-aws"
}

variable "hub_verticle_class" {
  description = "Hub Vert.x class list."
  type        = string
  default     = "ai.chronon.hub.AWSOrchestrationVerticle,ai.chronon.hub.AWSWorkflowExecutionVerticle"
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
  description = "Spark event log directory. Defaults to s3a://<warehouse_bucket>/spark-events."
  type        = string
  default     = ""
}

variable "spark_nvme_enabled" {
  description = "Whether to run the NVMe setup DaemonSet for Spark instance-store nodes."
  type        = bool
  default     = false
}

variable "spark_nvme_setup_image" {
  description = "Image used by the NVMe setup DaemonSet when spark_nvme_enabled is true."
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

variable "compute_image_prepull_images" {
  description = "Images prepulled onto compute nodes."
  type        = list(string)
  default     = []
}

variable "spark_history_extra_spark_opts" {
  description = "Additional Spark History Server JVM/Spark options."
  type        = list(string)
  default     = []
}

variable "polaris_storage_type" {
  description = "Polaris catalog storage type."
  type        = string
  default     = "S3"
}

variable "polaris_storage_config" {
  description = "Provider-specific Polaris storageConfigInfo fields."
  type        = any
  default     = {}
}

variable "polaris_allowed_locations" {
  description = "Allowed storage locations for the bootstrapped Polaris catalog."
  type        = list(string)
  default     = []
}

variable "polaris_default_base_location" {
  description = "Default base location for the bootstrapped Polaris catalog."
  type        = string
  default     = ""
}

variable "polaris_bootstrap_credentials_secret" {
  description = "Secret name containing or receiving Polaris bootstrap credentials."
  type        = string
  default     = "polaris-bootstrap-credentials"
}

variable "polaris_database_init_image" {
  description = "Image used by the Polaris database bootstrap init container."
  type        = string
  default     = "postgres:16-alpine"
}

variable "secret_provider_class_name" {
  description = "SecretProviderClass name mounted into orchestration pods."
  type        = string
  default     = "zipline-secret-provider"
}

variable "prometheus_query_endpoint" {
  description = "Prometheus query endpoint for the UI."
  type        = string
  default     = ""
}

variable "kv_table_prefix" {
  description = "DynamoDB table prefix used by the AWS Hub runtime."
  type        = string
  default     = ""
}

variable "kv_enable_ttl" {
  description = "Whether DynamoDB TTL is enabled."
  type        = bool
  default     = true
}

variable "kv_replica_regions" {
  description = "DynamoDB replica regions."
  type        = list(string)
  default     = []
}

variable "chronon_metrics_reader" {
  description = "Chronon metrics reader mode passed to Hub."
  type        = string
  default     = "http"
}

variable "aws_eks_log_group" {
  description = "Optional EKS container log group passed to the UI."
  type        = string
  default     = ""
}

variable "auth" {
  description = "Chart auth values object. Secrets are still read through auth_secret_arn."
  type        = any
  default = {
    enabled = false
  }
}

variable "auth_secret_arn" {
  description = "AWS Secrets Manager secret ARN containing auth-secret and OAuth secret JSON fields."
  type        = string
  default     = ""
}

variable "databricks_sp_secret_arn" {
  description = "Optional AWS Secrets Manager secret ARN containing client_id and client_secret for Databricks."
  type        = string
  default     = ""
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

variable "eval_env" {
  description = "Additional env vars passed only to eval."
  type        = any
  default     = []
}

variable "ui_env" {
  description = "Additional env vars passed only to the UI."
  type        = any
  default     = []
}

variable "fetcher_env" {
  description = "Additional env vars passed only to fetcher."
  type        = any
  default     = []
}

variable "image_pull_secret_name" {
  description = "Existing image pull secret name when create_image_pull_secret is false."
  type        = string
  default     = "docker-hub-creds"
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
  description = "Install the Secrets Store CSI driver."
  type        = bool
  default     = true
}

variable "install_aws_secrets_store_csi_provider" {
  description = "Install the AWS Secrets Store CSI provider."
  type        = bool
  default     = true
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

variable "install_aws_load_balancer_controller" {
  description = "Install the AWS Load Balancer Controller."
  type        = bool
  default     = true
}

variable "aws_load_balancer_controller_role_arn" {
  description = "IAM role ARN for the AWS Load Balancer Controller service account."
  type        = string
  default     = ""
}

variable "aws_load_balancer_controller_version" {
  description = "AWS Load Balancer Controller chart version."
  type        = string
  default     = "1.7.1"
}

variable "aws_load_balancer_scheme" {
  description = "AWS load balancer scheme used by ingress-nginx controller services."
  type        = string
  default     = "internet-facing"
}

variable "ingress_service_annotations" {
  description = "Extra annotations applied to every ingress-nginx controller Service."
  type        = map(string)
  default     = {}
}

variable "ingress_service_target_ports" {
  description = "Target ports applied to every ingress-nginx controller Service."
  type        = map(string)
  default     = {}
}

variable "ingress_annotations" {
  description = "Extra annotations applied to every application Ingress."
  type        = map(string)
  default     = {}
}

variable "ui_ingress_annotations" {
  description = "Extra annotations for the UI Ingress."
  type        = map(string)
  default     = {}
}

variable "hub_ingress_annotations" {
  description = "Extra annotations for the Hub Ingress."
  type        = map(string)
  default     = {}
}

variable "fetcher_ingress_annotations" {
  description = "Extra annotations for the fetcher Ingress."
  type        = map(string)
  default     = {}
}

variable "eval_ingress_annotations" {
  description = "Extra annotations for the eval Ingress."
  type        = map(string)
  default     = {}
}

variable "extra_secret_objects" {
  description = "Additional SecretProviderClass secretObjects entries."
  type        = any
  default     = []
}

variable "extra_secret_provider_objects" {
  description = "Additional AWS Secrets Store CSI provider objects."
  type        = any
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
