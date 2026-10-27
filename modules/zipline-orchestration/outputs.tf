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

output "ingress_controller_service_name" {
  description = "Name of the ingress-nginx controller Service created by the chart."
  value       = data.kubernetes_service_v1.ingress_controller.metadata[0].name
}

output "ingress_controller_service_namespace" {
  description = "Namespace of the ingress-nginx controller Service created by the chart."
  value       = data.kubernetes_service_v1.ingress_controller.metadata[0].namespace
}

output "ingress_load_balancer_hostname" {
  description = "Load balancer hostname for the public ingress controller, when the cloud provider publishes one."
  value       = try(data.kubernetes_service_v1.ingress_controller.status[0].load_balancer[0].ingress[0].hostname, "")
}

output "ingress_load_balancer_ip" {
  description = "Load balancer IP for the public ingress controller, when the cloud provider publishes one."
  value       = try(data.kubernetes_service_v1.ingress_controller.status[0].load_balancer[0].ingress[0].ip, "")
}

output "ingress_load_balancer_target" {
  description = "Provider-neutral DNS target for the public ingress controller. DNS overlays can route their record to this value."
  value = try(element(compact([
    try(data.kubernetes_service_v1.ingress_controller.status[0].load_balancer[0].ingress[0].hostname, ""),
    try(data.kubernetes_service_v1.ingress_controller.status[0].load_balancer[0].ingress[0].ip, ""),
  ]), 0), "")
}

output "read_only_orchestrator_service_url" {
  description = "Cluster-internal reader URL; null when the read-only server is disabled."
  value       = local.read_only.enabled ? "http://orchestration-read-only-service.${local.install.namespace}.svc.cluster.local" : null
}

output "read_only_orchestrator_hostname" {
  description = "Explicit reader ingress hostname; null when its ingress is disabled."
  value       = local.read_only.enabled && local.read_only_ingress.enabled ? local.read_only_ingress.host : null
}
