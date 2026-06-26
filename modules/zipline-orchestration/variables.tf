variable "chart_path" {
  description = "Path to the zipline-orchestration chart. Defaults to the repository-level charts/zipline-orchestration directory."
  type        = string
  default     = ""
}

variable "orchestration" {
  description = "Shared Zipline orchestration install inputs. Cloud wrappers pass this object through as the common interface."
  type        = any
}

variable "provider_context" {
  description = "Cloud wrapper values merged into orchestration before rendering shared Kubernetes resources."
  type        = any
  default     = {}
}
