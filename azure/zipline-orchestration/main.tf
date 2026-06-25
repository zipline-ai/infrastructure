module "zipline_orchestration" {
  source = "../../modules/zipline-orchestration"

  chart_path        = abspath("${path.module}/../../charts/zipline-orchestration")
  orchestration     = local.orchestration
  extra_values      = try(local.orchestration.extra_values, [])
  extra_values_yaml = try(local.orchestration.extra_values_yaml, [])
}
