output "ingress_load_balancer_hostname" {
  description = "Load balancer hostname for the public ingress controller."
  value       = module.zipline_orchestration.ingress_load_balancer_hostname
}

output "ingress_load_balancer_ip" {
  description = "Load balancer IP for the public ingress controller."
  value       = module.zipline_orchestration.ingress_load_balancer_ip
}

output "ingress_load_balancer_target" {
  description = "Provider-neutral DNS target for the public ingress controller."
  value       = module.zipline_orchestration.ingress_load_balancer_target
}
