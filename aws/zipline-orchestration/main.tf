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
      ] : trimspace(tostring(try(var.aws[key], ""))) != ""
    ])
    error_message = "aws must include non-empty warehouse_bucket and region."
  }

  # vpc_id/primary_subnet_id/secondary_subnet_id are provisioned on the fly when
  # omitted (see network.tf); supply all three together to bring your own network.
  validation {
    condition = (
      length(compact([
        trimspace(tostring(try(var.aws.vpc_id, ""))),
        trimspace(tostring(try(var.aws.primary_subnet_id, ""))),
        trimspace(tostring(try(var.aws.secondary_subnet_id, ""))),
      ])) == 0
      ) || (
      trimspace(tostring(try(var.aws.vpc_id, ""))) != "" &&
      trimspace(tostring(try(var.aws.primary_subnet_id, ""))) != "" &&
      trimspace(tostring(try(var.aws.secondary_subnet_id, ""))) != ""
    )
    error_message = "Set aws.vpc_id, aws.primary_subnet_id, and aws.secondary_subnet_id together to use an existing network, or omit all three to have Terraform create one."
  }

}

resource "terraform_data" "configuration_validation" {
  input = {
    auth_enabled       = local.auth_enabled
    auth_secret_arn    = local.configured_auth_secret_arn
    create_auth_secret = local.create_auth_secret
    redis_enabled      = local.redis.enabled
    redis_managed      = local.redis_managed
  }

  lifecycle {
    precondition {
      condition     = !local.auth_enabled || local.create_auth_secret || trimspace(local.configured_auth_secret_arn) != ""
      error_message = "When auth.enabled is true, set aws.auth_secret_arn, orchestration.auth.secrets_arn, or aws.auth_secret_values so the AWS wrapper can provide the auth secret."
    }

    precondition {
      condition     = !local.redis.enabled || local.redis_managed || trimspace(local.redis.password_secret_arn) == "" || startswith(trimspace(local.redis.password_secret_arn), "arn:")
      error_message = "aws.redis.password_secret_arn must be a Secrets Manager ARN when using an existing Redis cluster."
    }

    precondition {
      condition     = !local.redis_managed || (local.redis.shards >= 1 && local.redis.replicas_per_shard >= 0)
      error_message = "Managed Redis requires aws.redis.shards >= 1 and aws.redis.replicas_per_shard >= 0."
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
