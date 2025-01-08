
module "base_setup" {
  source = "../base-gcp"

  customer_name = var.customer_name
  region = var.region
  personnel_email = var.personnel_email
}
