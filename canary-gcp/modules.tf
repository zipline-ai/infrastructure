
module "base_setup" {
  source = "../base-gcp"

  customer_name = "canary"
  create_artifacts_bucket = true
}