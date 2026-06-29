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

  validation {
    condition     = !try(var.orchestration.auth.enabled, false) || trimspace(try(var.aws.auth_secret_arn, try(var.orchestration.auth.secrets_arn, ""))) != "" || length(keys(try(var.aws.auth_secret_values, {}))) > 0
    error_message = "When auth.enabled is true, set aws.auth_secret_arn, orchestration.auth.secrets_arn, or aws.auth_secret_values so the AWS wrapper can provide the auth secret."
  }

  validation {
    condition = alltrue([
      trimspace(try(var.aws.dns.cloudflare_api_token, "")) != "",
      trimspace(try(var.aws.dns.cloudflare_zone_id, "")) != "",
      trimspace(try(var.aws.dns.record_name, try(var.orchestration.ingress.domain, ""))) != "",
    ])
    error_message = "aws.dns must include cloudflare_api_token and cloudflare_zone_id, and either aws.dns.record_name or orchestration.ingress.domain must be set."
  }
}

module "zipline_orchestration" {
  source = "../../modules/zipline-orchestration"

  orchestration    = var.orchestration
  provider_context = local.provider_context

  depends_on = [
    aws_eks_addon.aws_ebs_csi_driver,
    aws_eks_node_group.default,
    helm_release.aws_load_balancer_controller,
    helm_release.fluent_bit,
    helm_release.secrets_store_csi_aws,
  ]
}
