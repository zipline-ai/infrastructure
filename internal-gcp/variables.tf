variable "region" {
  default = "US"
}

variable "customer_accts" {

  default = {
    canary = "gcp-admin@zipline.ai"
    etsy   = "gcp-zipline-admin@etsy.com"

  }
}

variable "service_accts" {
  default = {
    canary = []
    etsy = [
      "gke-mirror-sa-airflow@etsy-batchjobs-prod.iam.gserviceaccount.com",
      "buildkite-default@etsy-buildkite-prod.iam.gserviceaccount.com",
    ]
  }
}

variable "customer_projects" {

  default = {
    canary = "canary-443022"
    dev    = "canary-443022"
    etsy   = "etsy-zipline-dev"

  }
}
