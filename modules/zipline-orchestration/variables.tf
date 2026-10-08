variable "chart_path" {
  description = "Path to the zipline-orchestration chart. Defaults to the repository-level charts/zipline-orchestration directory."
  type        = string
  default     = ""
}

variable "orchestration" {
  description = "Shared Zipline orchestration install inputs. Cloud wrappers pass this object through as the common interface."
  type        = any

  validation {
    condition = (
      try(var.orchestration.data_explorer.enabled, false) == true ||
      try(var.orchestration.data_explorer.enabled, false) == false
    )
    error_message = "orchestration.data_explorer.enabled must be a boolean."
  }
}

variable "provider_context" {
  description = "Cloud wrapper values merged into orchestration before rendering shared Kubernetes resources."
  type        = any
  default     = {}
}
