variable "orchestration" {
  description = "Shared Zipline orchestration install inputs consumed by modules/zipline-orchestration."
  type        = any
}

variable "aws" {
  description = "AWS-specific orchestration wrapper inputs."
  type        = any

  validation {
    condition = alltrue([
      for key in [
        "warehouse_bucket",
        "region",
        "spark_compute_role_arn",
        "orchestration_role_arn",
        "database_secret_arn",
      ] : trimspace(tostring(try(var.aws[key], ""))) != ""
    ])
    error_message = "aws must include non-empty warehouse_bucket, region, spark_compute_role_arn, orchestration_role_arn, and database_secret_arn."
  }

  validation {
    condition     = !try(var.orchestration.auth.enabled, false) || trimspace(try(var.aws.auth_secret_arn, "")) != ""
    error_message = "auth_secret_arn must be set when auth.enabled is true."
  }
}

module "zipline_orchestration" {
  source = "../../modules/zipline-orchestration"

  orchestration    = var.orchestration
  provider_context = local.provider_context
}
