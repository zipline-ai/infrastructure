variable "orchestration" {
  description = "Shared Zipline orchestration install inputs consumed by modules/zipline-orchestration."
  type        = any
}

variable "aws" {
  description = "AWS-specific orchestration wrapper inputs."
  type        = any

  validation {
    condition     = !strcontains(var.aws.warehouse_bucket, "://")
    error_message = "aws.warehouse_bucket must be a bucket name only, not a URI."
  }
}
