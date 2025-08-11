
module "base_setup" {
  source = "../base-gcp"

  customer_name = "canary"

  artifact_prefix = "gs://zipline-canary-artifacts"
  topic_id = "canary-testing"
}

output "setup_instructions" {
  value = module.base_setup.setup_instructions
}