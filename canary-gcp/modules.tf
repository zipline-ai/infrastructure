
module "base_setup" {
  source = "../base-gcp"

  customer_name = "canary"

  artifact_prefix = "gs://zipline-canary-artifacts"
  topic_id = "canary-testing"
  zipline_version = "v0.10.0"
}

output "setup_instructions" {
  value = module.base_setup.setup_instructions
}