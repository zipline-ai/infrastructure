variable "region" {
  default = "us-central1"
}

variable "zone" {
    default = "us-central1-a"
}


variable "customer_name" {
  default = "canary"
}

variable "personnel_email" {
    default = "gcp-admin@zipline.ai"
}

variable "dataproc-subnetwork" {
    default = ""
}

variable "create_warehouse_bucket" {
  default = false # default false because we expect this to only be in customer vpc
}