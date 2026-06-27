output "release_name" {
  description = "Name of the Helm release."
  value       = helm_release.this.name
}

output "namespace" {
  description = "Namespace where the Helm release is installed."
  value       = helm_release.this.namespace
}

output "chart_path" {
  description = "Resolved chart path used by the Helm release."
  value       = local.chart_path
}
