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

variable "hub_domain" {
  description = "Public hostname for the orchestration Hub."
  type        = string
  default     = ""
}

variable "hub_external_url" {
  description = "Explicit public Hub URL. When unset the chart derives it from hub_domain."
  type        = string
  default     = ""
}

variable "ui_domain" {
  description = "Public hostname for the orchestration UI."
  type        = string
  default     = ""
}

variable "fetcher_domain" {
  description = "Public hostname for fetcher."
  type        = string
  default     = ""
}

variable "eval_domain" {
  description = "Public hostname for eval."
  type        = string
  default     = ""
}

variable "ui_tls_secret_name" {
  description = "Kubernetes TLS secret for the UI ingress. Leave empty to render no TLS block."
  type        = string
  default     = ""
}

variable "hub_tls_secret_name" {
  description = "Kubernetes TLS secret for the Hub ingress. Leave empty to render no TLS block."
  type        = string
  default     = ""
}

variable "fetcher_tls_secret_name" {
  description = "Kubernetes TLS secret for fetcher. Leave empty to render no TLS block."
  type        = string
  default     = ""
}

variable "eval_tls_secret_name" {
  description = "Kubernetes TLS secret for eval. Leave empty to render no TLS block."
  type        = string
  default     = ""
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

variable "polaris_bootstrap_credentials_secret" {
  description = "Secret name containing or receiving Polaris bootstrap credentials."
  type        = string
  default     = "polaris-bootstrap-credentials"
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

variable "emr_serverless_execution_role_arn" {
  description = "Optional EMR Serverless execution role ARN for legacy AWS runtime compatibility."
  type        = string
  default     = ""
}

variable "emr_log_uri" {
  description = "Optional EMR log URI for legacy AWS runtime compatibility."
  type        = string
  default     = ""
}

variable "emr_cloudwatch_log_group" {
  description = "Optional EMR CloudWatch log group for legacy AWS runtime compatibility."
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

variable "ui_ingress_service_annotations" {
  description = "Extra annotations for the UI ingress-nginx controller Service."
  type        = map(string)
  default     = {}
}

variable "hub_ingress_service_annotations" {
  description = "Extra annotations for the Hub ingress-nginx controller Service."
  type        = map(string)
  default     = {}
}

variable "fetcher_ingress_service_annotations" {
  description = "Extra annotations for the fetcher ingress-nginx controller Service."
  type        = map(string)
  default     = {}
}

variable "eval_ingress_service_annotations" {
  description = "Extra annotations for the eval ingress-nginx controller Service."
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
