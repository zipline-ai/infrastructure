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