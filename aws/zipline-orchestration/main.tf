resource "terraform_data" "configuration_validation" {
  input = {
    auth_enabled = local.auth_enabled
  }

  lifecycle {
    precondition {
      condition     = !local.auth_enabled || trimspace(local.aws.auth_secret_arn) != ""
      error_message = "auth_secret_arn must be set when auth.enabled is true."
    }
  }
}

module "zipline_orchestration" {
  source = "../../modules/zipline-orchestration"

  chart_path        = abspath("${path.module}/../../charts/zipline-orchestration")
  orchestration     = local.orchestration
  values            = local.provider_values
  extra_values      = try(local.orchestration.extra_values, [])
  extra_values_yaml = try(local.orchestration.extra_values_yaml, [])

  depends_on = [
    terraform_data.configuration_validation,
  ]
}
