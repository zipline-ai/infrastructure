variable "chart_path" {
  description = "Path to the zipline-orchestration chart supplied by the cloud installation wrapper."
  type        = string
}

variable "orchestration" {
  description = "Shared Zipline orchestration install inputs. Cloud wrappers pass this object through as the common interface."
  type        = any
}
