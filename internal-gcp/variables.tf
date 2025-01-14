variable "region" {
  default = "US"
}

variable "customer_names" {
  type = set(string)
  default = [
    "canary",
    "etsy"
  ]
}

variable "personnel_email" {
  default = "gcp-admin@zipline.ai"
}