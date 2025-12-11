variable "region" {
  default = "us-west-2"
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

variable "control_plane_account_id" {
  default = "345594603419"
}