module "zipline_orchestration" {
  source = "../../modules/zipline-orchestration"

  chart_path    = abspath("${path.module}/../../charts/zipline-orchestration")
  orchestration = merge(local.orchestration, { values = local.provider_values })
}
