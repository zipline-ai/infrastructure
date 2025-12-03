variable "project_id" {}

variable "project_number" {}

variable "name_prefix" {}

variable "docker_hub_token" {}

variable "personnel_email" {}

variable "alerting_email" {}

variable "zipline_version" {}

variable "region" {}

variable "hub_domain" {
  description = "Set to provide a URL for the Zipline hub."
  default     = ""
}

variable "zipline_ui_domain" {
  description = "Set to provide a URL for the Zipline frontend."
  default     = ""
}

variable "vpc_id" {}

variable "vpc_name" {}

variable "subnet_name" {}

variable "bigtable_instance_name" {}

variable "logs_bucket_name" {}

variable "artifact_prefix" {}

variable "table_partitions_dataset" {}

variable "data_quality_metrics_dataset" {}

variable "dataproc_service_account" {}

variable "eval_impersonation_users" {
  description = "List of users/groups who can impersonate the eval service account (e.g., user:alice@example.com, group:data-team@example.com)"
  type        = list(string)
  default     = []
}