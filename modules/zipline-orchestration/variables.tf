variable "chart_path" {
  description = "Path to the zipline-orchestration chart supplied by the cloud installation wrapper."
  type        = string
}

variable "orchestration" {
  description = "Shared Zipline orchestration install inputs. Cloud wrappers pass this object through as the common interface."
  type        = any
}

variable "values" {
  description = "Cloud-specific Helm values merged after the module-generated common values."
  type        = any
  default     = {}
}

variable "extra_values" {
  description = "Additional values objects merged after values."
  type        = list(any)
  default     = []
}

variable "extra_values_yaml" {
  description = "Additional raw YAML values merged after values and extra_values."
  type        = list(string)
  default     = []
}
