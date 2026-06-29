locals {
  dns = merge({
    cloudflare_api_token = ""
    cloudflare_zone_id   = ""
    record_name          = try(var.orchestration.ingress.domain, "")
  }, try(local.cloud_args.dns, {}))
}

data "kubernetes_service_v1" "ui_nginx" {
  metadata {
    name      = "zipline-orchestration-ingress-nginx-ui-controller"
    namespace = module.zipline_orchestration.namespace
  }

  depends_on = [module.zipline_orchestration]
}

module "public_dns" {
  source = "../../modules/cloudflare-dns"

  api_token   = local.dns.cloudflare_api_token
  zone_id     = local.dns.cloudflare_zone_id
  record_name = local.dns.record_name
  target      = data.kubernetes_service_v1.ui_nginx.status[0].load_balancer[0].ingress[0].hostname
}
