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