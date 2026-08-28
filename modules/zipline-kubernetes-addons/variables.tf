variable "install_external_secrets_operator" {
  description = "Install External Secrets Operator."
  type        = bool
  default     = false
}

variable "external_secrets_operator_version" {
  description = "External Secrets Operator chart version."
  type        = string
  default     = "2.7.0"
}

variable "external_secrets_operator_values" {
  description = "Additional External Secrets Operator chart values."
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

variable "install_kuberay_operator" {
  description = "Install the KubeRay operator and its custom resource definitions."
  type        = bool
  default     = true
}

variable "kuberay_operator_version" {
  description = "KubeRay operator chart version."
  type        = string
  default     = "1.7.0"
}

variable "kuberay_operator_skip_crds" {
  description = "Skip installing KubeRay custom resource definitions. Use when the CRDs are managed separately."
  type        = bool
  default     = false
}

variable "kuberay_operator_values" {
  description = "Additional KubeRay operator chart values."
  type        = any
  default     = {}
}

variable "install_metrics_server" {
  description = "Install Metrics Server for Kubernetes resource metrics and HPA."
  type        = bool
  default     = true
}

variable "metrics_server_version" {
  description = "Metrics Server chart version."
  type        = string
  default     = "3.13.1"
}

variable "metrics_server_values" {
  description = "Additional Metrics Server chart values."
  type        = any
  default = {
    args = [
      "--kubelet-preferred-address-types=InternalIP,Hostname,InternalDNS,ExternalDNS,ExternalIP",
      "--kubelet-insecure-tls",
    ]
  }
}
