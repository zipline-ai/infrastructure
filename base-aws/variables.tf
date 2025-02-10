variable "region" {
  default = "us-west-1"
}

variable "customer_name" {
  default = "canary"
}

variable "emr_subnetwork" {
  default = ""
}

variable "emr_tags" {
  default = {}
}

variable "emr_bootstrap_actions" {
  default = {}
}