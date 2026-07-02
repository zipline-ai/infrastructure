variable "orchestration" {
  description = "Shared Zipline orchestration install inputs consumed by modules/zipline-orchestration."
  type        = any
}

variable "aws" {
  description = "AWS-specific orchestration wrapper inputs."
  type        = any

  validation {
    condition = alltrue([
      for key in [
        "warehouse_bucket",
        "region",
        "vpc_id",
        "primary_subnet_id",
        "secondary_subnet_id",
      ] : trimspace(tostring(try(var.aws[key], ""))) != ""
    ])
    error_message = "aws must include non-empty warehouse_bucket, region, vpc_id, primary_subnet_id, and secondary_subnet_id."
  }

}

resource "terraform_data" "configuration_validation" {
  input = {
    auth_enabled       = local.auth_enabled
    auth_secret_arn    = local.configured_auth_secret_arn
    create_auth_secret = local.create_auth_secret
  }

  lifecycle {
    precondition {
      condition     = !local.auth_enabled || local.create_auth_secret || trimspace(local.configured_auth_secret_arn) != ""
      error_message = "When auth.enabled is true, set aws.auth_secret_arn, orchestration.auth.secrets_arn, or aws.auth_secret_values so the AWS wrapper can provide the auth secret."
    }
  }
}

module "zipline_orchestration" {
  source = "../../modules/zipline-orchestration"

  orchestration    = local.module_orchestration
  provider_context = local.provider_context

  depends_on = [
    aws_eks_addon.aws_ebs_csi_driver,
    aws_eks_node_group.default,
    kubernetes_storage_class_v1.gp3,
    helm_release.aws_load_balancer_controller,
    helm_release.fluent_bit,
    helm_release.karpenter_nodepools,
    terraform_data.configuration_validation,
  ]
}
