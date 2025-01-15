variable "region" {
  default = "US"
}

variable "customer_accts" {

  default = {
    canary = "gcp-admin@zipline.ai"
    etsy = "gcp-zipline-admin@etsy.com"

  }
}
