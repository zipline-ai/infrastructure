
module "base_setup" {
  source = "../base-gcp"
  artifact_prefix = var.artifact_prefix
  zipline_version = var.zipline_version

  customer_name = var.customer_name
  region = var.region
  personnel_email = var.personnel_email
  zone = var.bigtable_zone

  hub_domain = var.hub_domain
  zipline_ui_domain = var.zipline_ui_domain


}
