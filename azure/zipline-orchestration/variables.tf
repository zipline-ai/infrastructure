variable "orchestration" {
  description = "Shared Zipline orchestration install inputs consumed by modules/zipline-orchestration."
  type        = any
}

variable "azure" {
  description = "Azure-specific orchestration wrapper inputs."
  type        = any
}
