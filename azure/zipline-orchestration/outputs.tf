output "namespace" {
  description = "Namespace where Zipline orchestration is installed."
  value       = module.zipline_orchestration.namespace
}

output "release_name" {
  description = "Zipline orchestration Helm release name."
  value       = module.zipline_orchestration.release_name
}

output "chart_path" {
  description = "Resolved chart path used by the Helm release."
  value       = module.zipline_orchestration.chart_path
}
