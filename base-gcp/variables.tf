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

variable "create_artifacts_bucket" {
  default = false # default false because we expect users to create this in the customer vpc 
}