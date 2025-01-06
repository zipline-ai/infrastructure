
module "base_setup" {
  source = "../base-gcp"

  name = var.customer_name
  region = var.region
}
