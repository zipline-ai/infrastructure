variable "orchestration" {
  description = "Shared Zipline orchestration install inputs consumed by modules/zipline-orchestration."
  type        = any
}

variable "azure" {
  description = "Azure-specific orchestration wrapper inputs."
  type        = any

  validation {
    condition     = !strcontains(var.azure.warehouse_container_name, "://")
    error_message = "azure.warehouse_container_name must be a container name only, not a URI."
  }
}
