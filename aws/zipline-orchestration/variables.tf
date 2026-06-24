variable "orchestration" {
  description = "Shared Zipline orchestration install inputs consumed by modules/zipline-orchestration."
  type        = any
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

variable "polaris_storage_config" {
  description = "Provider-specific Polaris storageConfigInfo fields."
  type        = any
  default     = {}
}

variable "secret_provider_class_name" {
  description = "SecretProviderClass name mounted into orchestration pods."
  type        = string
  default     = "zipline-secret-provider"
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

variable "install_aws_secrets_store_csi_provider" {
  description = "Install the AWS Secrets Store CSI provider."
  type        = bool
  default     = true
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
  description = "Extra annotations applied to ingress-nginx controller Services."
  type        = map(string)
  default     = {}
}

variable "ingress_service_target_ports" {
  description = "Target ports applied to ingress-nginx controller Services."
  type        = map(string)
  default     = {}
}

variable "extra_secret_provider_objects" {
  description = "Additional AWS Secrets Store CSI provider objects."
  type        = any
  default     = []
}
