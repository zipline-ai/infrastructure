
module "base_setup" {
  source = "../base-gcp"

  customer_name = "canary"
  create_warehouse_bucket = true
}