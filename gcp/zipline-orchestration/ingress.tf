# Reserve a regional external IP that the ingress-nginx Service picks up via
# spec.loadBalancerIP. The chart's `ingress-nginx-ui.controller.service.*` keys
# surface this through provider_values.
resource "google_compute_address" "ingress" {
  count = local.cloud_args.ingress_load_balancer_ip == "" ? 1 : 0

  name         = "${local.name_prefix}-ingress"
  address_type = "EXTERNAL"
  region       = local.cloud_args.region
}

locals {
  ingress_lb_ip = local.cloud_args.ingress_load_balancer_ip != "" ? local.cloud_args.ingress_load_balancer_ip : google_compute_address.ingress[0].address

  # §8: GKE's L4 LB (NetworkLoadBalancer) is produced by Service type=LoadBalancer.
  # externalTrafficPolicy=Local preserves client IPs but requires the ingress
  # pod to be on every target node; Cluster is the default-safe choice until
  # we have a reason to switch.
  ingress_lb_service = {
    loadBalancerIP        = local.ingress_lb_ip
    externalTrafficPolicy = local.cloud_args.ingress_traffic_policy
    annotations = {
      "cloud.google.com/l4-rbs" = "enabled"
    }
  }
}
