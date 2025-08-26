variable "region" {
  default = "us-central1"
}

variable "zone" {
  default = "us-central1-f"
}


variable "customer_name" {
  default = "canary"
}

variable "personnel_email" {
  default = "gcp-admin@zipline.ai"
}

variable "dataproc_subnetwork" {
  default = ""
}

variable "dataproc_tags" {
  default = []
}

variable "dataproc_init_actions" {
  default = []
}

variable "control_plane_service_account" {
  default = "logs-viewer@zipline-main.iam.gserviceaccount.com"
}

variable "artifact_prefix" {
  description = "The GCS path prefix for storing artifacts. e.g. gs://my-bucket/artifacts"
}

variable "hub_domain" {
  description = "Optional custom domain for hub. If not set, a default domain will be used."
  default     = ""
}

variable "temporal_domain" {
  description = "Optional custom domain for the Temporal UI. If not set, a default domain will be used."
  default     = ""
}

variable "zipline_ui_domain" {
  description = "Optional custom domain for the Zipline UI. If not set, a default domain will be used."
  default     = ""
}

variable "zipline_version" {
  description = "The version of Zipline to deploy. This should correspond to a valid Docker image tag in the Zipline repository."
  default     = "latest"
}