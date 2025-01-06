
module "base_setup" {
  source = "../base-gcp"

  name = var.name
  region = var.region
}
