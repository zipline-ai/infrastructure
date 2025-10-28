variable "customer_name" {}
variable "project" {}
variable "region" {}
variable "personnel_email" {
  description = "Group email for personnel who will administer the Zipline deployment."
}
variable "users_email" {
  description = "Group email for users who will access the Zipline deployment."
  default = ""
}
variable "alerting_email" {
  description = "Email address to send alerts to."
  default = ""
}
variable "bigtable_zone" {}
variable "artifact_prefix" {}
variable "zipline_version" {
  default = "v0.13.0"
}
variable "hub_domain" {
  description = "Optional custom domain for hub. If not set, a default domain will be used."
  default     = ""
}

variable "zipline_ui_domain" {
  description = "Optional custom domain for the Zipline UI. If not set, a default domain will be used."
  default     = ""
}

variable "vpc_network_name" {
  description = "The name of the VPC network to deploy resources into. If not set, one will be created."
  default = ""
}

variable "vpc_network_id" {
  description = "The id of the VPC network to deploy resources into. If not set, one will be created."
  default = ""
}

variable "vpc_subnet_name" {
  description = "The name of the VPC subnet to deploy resources into. If not set, one will be created."
  default = ""
}