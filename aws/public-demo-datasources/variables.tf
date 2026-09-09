variable "aws_region" {
  description = "AWS region for the public-demo datasource layer."
  type        = string
}

variable "name_prefix" {
  description = "Prefix used for public-demo datasource resources."
  type        = string
  default     = "public-demo"
}

variable "raw_bucket" {
  description = "S3 bucket for raw public-demo datasource snapshots."
  type        = string
}

variable "curated_bucket" {
  description = "S3 bucket reserved for curated public-demo datasets."
  type        = string
}

variable "warehouse_bucket" {
  description = "S3 bucket used by the public-demo Chronon warehouse."
  type        = string
}

variable "ui_logs_enabled" {
  description = "Enable the Kubernetes UI/server log datasource for the public demo."
  type        = bool
  default     = true
}

variable "ui_logs_glue_database_name" {
  description = "Glue database for public-demo app/UI log tables."
  type        = string
  default     = "public_demo_app"
}

variable "ui_logs_table_name" {
  description = "Glue table containing parsed UI and ingress access logs."
  type        = string
  default     = "ui_access_logs"
}

variable "ui_logs_output_prefix" {
  description = "Curated bucket prefix for parsed UI and ingress access logs."
  type        = string
  default     = "app/ui_access_logs"
}

variable "user_identity_table_name" {
  description = "Glue table containing auth user identity snapshots with hashed email values."
  type        = string
  default     = "user_identity_snapshots"
}

variable "user_identity_output_prefix" {
  description = "Curated bucket prefix for auth user identity snapshots."
  type        = string
  default     = "app/user_identity_snapshots"
}

variable "user_identity_parquet_output_prefix" {
  description = "Curated bucket prefix for Parquet auth identity snapshots read directly by Spark."
  type        = string
  default     = "app/user_identity_snapshots_parquet"
}

variable "user_identity_iceberg_table_name" {
  description = "Glue Iceberg table populated by the auth identity ingestor for Spark consumption."
  type        = string
  default     = "user_identity_snapshots_iceberg"
}

variable "user_identity_iceberg_output_prefix" {
  description = "Curated bucket prefix for the Lambda-managed auth identity Iceberg table."
  type        = string
  default     = "app/user_identity_snapshots_iceberg"
}

variable "aws_sdk_pandas_layer_arn" {
  description = "AWS SDK for pandas Lambda layer providing PyArrow for Parquet output."
  type        = string
  default     = "arn:aws:lambda:us-west-2:336392948345:layer:AWSSDKPandas-Python312:29"
}

variable "user_identity_snapshot_days" {
  description = "Number of daily auth identity snapshot partitions to materialize per ingestor run. This is intentionally low-cost, but can be raised for demos that need broader backfills."
  type        = number
  default     = 21
}

variable "ui_logs_log_group_name" {
  description = "CloudWatch log group that receives EKS container logs from Fluent Bit."
  type        = string
  default     = ""
}

variable "ui_logs_log_stream_prefixes" {
  description = "Optional CloudWatch log stream prefixes to narrow the UI log scan. Empty scans the full log group and parses only HTTP access log lines."
  type        = list(string)
  default     = []
}

variable "ui_logs_freshness_profile" {
  description = "Single freshness/cost lever for UI log harvesting."
  type        = string
  default     = "low_cost"

  validation {
    condition     = contains(["low_cost", "balanced", "fresh"], var.ui_logs_freshness_profile)
    error_message = "ui_logs_freshness_profile must be one of: low_cost, balanced, fresh."
  }
}
