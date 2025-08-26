
module "base_setup" {
  source = "../base-gcp"

  customer_name = "canary"

  artifact_prefix = "gs://zipline-canary-artifacts"
  zipline_version = "212a8e714e758db2119f7cf297616c8398b5567a"
}
