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
  default = ""
}

variable "temporal_domain" {
  default = ""
}

variable "zipline_ui_domain" {
  default = ""
}

variable "artifact_prefix" {
  default = "gs://zipline-artifacts-canary"
}

variable "data_quality_metrics_dataset" {
  description = "The Bigtable table to use for storing table data quality metrics."
  default     = "DATA_QUALITY_METRICS"
}

variable "data_quality_metrics_ci_dataset" {
  description = "The Bigtable table to use for storing table data quality metrics (in CI)."
  default     = "DATA_QUALITY_METRICS_CI"

}