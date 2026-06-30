variable "install_secrets_store_csi_driver" {
  description = "Install the Kubernetes Secrets Store CSI driver."
  type        = bool
  default     = false
}

variable "secrets_store_csi_driver_version" {
  description = "Secrets Store CSI driver chart version."
  type        = string
  default     = "1.4.1"
}

variable "secrets_store_csi_driver_values" {
  description = "Additional Secrets Store CSI driver chart values."
  type        = any
  default     = {}
}

variable "install_cert_manager" {
  description = "Install cert-manager for ingress TLS and webhook dependencies."
  type        = bool
  default     = true
}

variable "cert_manager_version" {
  description = "cert-manager chart version."
  type        = string
  default     = "v1.13.3"
}

variable "cert_manager_values" {
  description = "Additional cert-manager chart values."
  type        = any
  default     = {}
}

variable "install_opentelemetry_operator" {
  description = "Install the OpenTelemetry operator."
  type        = bool
  default     = false
}

variable "opentelemetry_operator_version" {
  description = "OpenTelemetry operator chart version."
  type        = string
  default     = "0.47.0"
}

variable "opentelemetry_operator_values" {
  description = "Additional OpenTelemetry operator chart values."
  type        = any
  default     = {}
}

variable "install_flink_operator" {
  description = "Install the Apache Flink Kubernetes operator."
  type        = bool
  default     = true
}

variable "flink_operator_version" {
  description = "Flink Kubernetes operator chart version."
  type        = string
  default     = "1.14.0"
}

variable "flink_operator_values" {
  description = "Additional Flink Kubernetes operator chart values."
  type        = any
  default     = {}
}
