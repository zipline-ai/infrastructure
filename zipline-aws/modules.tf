
module "base_setup" {
  source = "../base-aws"

  customer_name = var.customer_name
  region = var.region
}
