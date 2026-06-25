resource "terraform_data" "configuration_validation" {
  input = {
    auth_enabled                         = local.auth_enabled
    install_aws_load_balancer_controller = local.aws.install_load_balancer_controller
  }

  lifecycle {
    precondition {
      condition     = !local.auth_enabled || trimspace(local.aws.auth_secret_arn) != ""
      error_message = "auth_secret_arn must be set when auth.enabled is true."
    }

    precondition {
      condition     = !local.aws.install_load_balancer_controller || trimspace(local.aws.load_balancer_controller_role_arn) != ""
      error_message = "aws_load_balancer_controller_role_arn must be set when install_aws_load_balancer_controller is true."
    }

    precondition {
      condition     = !local.aws.install_load_balancer_controller || trimspace(local.aws.vpc_id) != ""
      error_message = "vpc_id must be set when install_aws_load_balancer_controller is true."
    }
  }
}

resource "helm_release" "secrets_store_csi_provider_aws" {
  count = local.aws.install_secrets_store_csi_provider ? 1 : 0

  name       = "secrets-store-csi-driver-provider-aws"
  repository = "https://aws.github.io/secrets-store-csi-driver-provider-aws"
  chart      = "secrets-store-csi-driver-provider-aws"
  namespace  = "kube-system"
  version    = "0.3.6"
}

resource "helm_release" "aws_load_balancer_controller" {
  count = local.aws.install_load_balancer_controller ? 1 : 0

  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = local.aws.load_balancer_controller_version

  values = [
    yamlencode({
      clusterName = local.aws.cluster_name
      region      = local.aws.region
      vpcId       = local.aws.vpc_id
      serviceAccount = {
        create = true
        name   = "aws-load-balancer-controller"
        annotations = {
          "eks.amazonaws.com/role-arn" = local.aws.load_balancer_controller_role_arn
        }
      }
    })
  ]
}

module "zipline_orchestration" {
  source = "../../modules/zipline-orchestration"

  chart_path        = abspath("${path.module}/../../charts/zipline-orchestration")
  orchestration     = local.orchestration
  extra_values      = try(local.orchestration.extra_values, [])
  extra_values_yaml = try(local.orchestration.extra_values_yaml, [])

  depends_on = [
    terraform_data.configuration_validation,
    helm_release.secrets_store_csi_provider_aws,
    helm_release.aws_load_balancer_controller,
  ]
}
