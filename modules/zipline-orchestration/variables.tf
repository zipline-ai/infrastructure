variable "release_name" {
  description = "Helm release name for the Zipline orchestration chart."
  type        = string
  default     = "zipline-orchestration"
}

variable "namespace" {
  description = "Kubernetes namespace where Zipline orchestration is installed."
  type        = string
  default     = "zipline-system"
}

variable "create_namespace" {
  description = "Whether this module should create the release namespace."
  type        = bool
  default     = true
}

variable "namespace_labels" {
  description = "Labels to apply when create_namespace is true."
  type        = map(string)
  default     = {}
}

variable "namespace_annotations" {
  description = "Annotations to apply when create_namespace is true."
  type        = map(string)
  default     = {}
}

variable "chart_path" {
  description = "Path to the zipline-orchestration chart. Defaults to the repository top-level charts directory."
  type        = string
  default     = null
}

variable "values" {
  description = "Primary values object passed to the Zipline orchestration Helm chart."
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

variable "wait" {
  description = "Whether Helm waits for all resources to become ready."
  type        = bool
  default     = false
}

variable "timeout" {
  description = "Helm operation timeout in seconds."
  type        = number
  default     = 600
}

variable "atomic" {
  description = "Whether Helm rolls back failed installs or upgrades."
  type        = bool
  default     = false
}

variable "cleanup_on_fail" {
  description = "Whether Helm deletes newly-created resources after a failed upgrade."
  type        = bool
  default     = false
}

variable "dependency_update" {
  description = "Whether Helm should update chart dependencies before installing."
  type        = bool
  default     = false
}
