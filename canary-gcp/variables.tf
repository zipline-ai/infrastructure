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
  default = "gs://zipline-canary-artifacts"
}

variable "zipline_version" {
  default = "212a8e714e758db2119f7cf297616c8398b5567a"
}