resource "terraform_data" "configuration_validation" {
  input = {
    auth_enabled                         = local.auth_enabled
    install_aws_load_balancer_controller = var.install_aws_load_balancer_controller
  }

  lifecycle {
    precondition {
      condition     = !local.auth_enabled || trimspace(var.auth_secret_arn) != ""
      error_message = "auth_secret_arn must be set when auth.enabled is true."
    }

    precondition {
      condition     = !var.install_aws_load_balancer_controller || trimspace(var.aws_load_balancer_controller_role_arn) != ""
      error_message = "aws_load_balancer_controller_role_arn must be set when install_aws_load_balancer_controller is true."
    }

    precondition {
      condition     = !var.install_aws_load_balancer_controller || trimspace(var.vpc_id) != ""
      error_message = "vpc_id must be set when install_aws_load_balancer_controller is true."
    }
  }
}

resource "helm_release" "secrets_store_csi_provider_aws" {
  count = var.install_aws_secrets_store_csi_provider ? 1 : 0

  name       = "secrets-store-csi-driver-provider-aws"
  repository = "https://aws.github.io/secrets-store-csi-driver-provider-aws"
  chart      = "secrets-store-csi-driver-provider-aws"
  namespace  = "kube-system"
  version    = "0.3.6"
}

resource "helm_release" "aws_load_balancer_controller" {
  count = var.install_aws_load_balancer_controller ? 1 : 0

  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = var.aws_load_balancer_controller_version

  values = [
    yamlencode({
      clusterName = var.cluster_name
      region      = var.region
      vpcId       = var.vpc_id
      serviceAccount = {
        create = true
        name   = "aws-load-balancer-controller"
        annotations = {
          "eks.amazonaws.com/role-arn" = var.aws_load_balancer_controller_role_arn
        }
      }
    })
  ]
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
    helm_release.secrets_store_csi_provider_aws,
    helm_release.aws_load_balancer_controller,
  ]
}
