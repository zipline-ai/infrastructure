variable "region" {
  default = "us-central1"
}

variable "name" {
  default = "canary"
}

variable "personnel_email" {
  default = "gcp-admin@zipline.ai"
}

variable "hub_domain" {
  default = "canary-orch.zipline.ai"
}

variable "zipline_ui_domain" {
  default = "canary.zipline.ai"
}

variable "dev_hub_domain" {
  default = "dev-orch.zipline.ai"
}

variable "dev_zipline_ui_domain" {
  default = "dev.zipline.ai"
}

variable "artifact_prefix" {
  default = "gs://zipline-artifacts-canary"
}

variable "docker_hub_token" {
  description = "Docker Hub token for pulling Zipline Docker images. If you have not been provided one, please reach out to the Zipline team."
  default     = "dckr_oat_Wk7MiSwlSNojzNJI2HPCqKIeZ1sRLI2x"
}

variable "data_quality_metrics_dataset" {
  description = "The Bigtable table to use for storing table data quality metrics."
  default     = "DATA_QUALITY_METRICS"
}

variable "data_quality_metrics_ci_dataset" {
  description = "The Bigtable table to use for storing table data quality metrics (in CI)."
  default     = "DATA_QUALITY_METRICS_CI"
}

variable "eval_impersonation_users" {
  description = "List of users/groups who can impersonate the eval service account"
  type        = list(string)
  default     = ["domain:zipline.ai"]
}