variable "orchestration" {
  description = "Shared Zipline orchestration install inputs consumed by modules/zipline-orchestration."
  type        = any
}

variable "aws" {
  description = "AWS-specific orchestration wrapper inputs."
  type        = any
}

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

  chart_path    = abspath("${path.module}/../../charts/zipline-orchestration")
  orchestration = merge(local.orchestration, { values = local.provider_values })

  depends_on = [
    terraform_data.configuration_validation,
  ]
}
