variable "region" {
  default = "US"
}

variable "customer_accts" {

  default = {
    canary = "gcp-admin@zipline.ai"
    etsy   = "gcp-zipline-admin@etsy.com"

  }
}

variable "customer_projects" {

  default = {
    canary    = "canary-443022"
    canary-ci = "canary-443022"
    etsy      = "etsy-zipline-dev"

  }
}
