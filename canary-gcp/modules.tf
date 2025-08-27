
module "base_setup" {
  source = "../base-gcp"

  customer_name = "canary"

  artifact_prefix = "gs://zipline-canary-artifacts"
  zipline_version = "2768066dd98c0d5930e111eb7150880b5d3ae971"
}
