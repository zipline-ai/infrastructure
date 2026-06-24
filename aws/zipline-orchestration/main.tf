resource "kubernetes_namespace_v1" "zipline_system" {
  metadata {
    name        = var.namespace
    labels      = var.namespace_labels
    annotations = var.namespace_annotations
  }
}

resource "terraform_data" "configuration_validation" {
  input = {
    auth_enabled                         = local.auth_enabled
    create_image_pull_secret             = var.create_image_pull_secret
    install_aws_load_balancer_controller = var.install_aws_load_balancer_controller
  }

  lifecycle {
    precondition {
      condition     = !local.auth_enabled || trimspace(var.auth_secret_arn) != ""
      error_message = "auth_secret_arn must be set when auth.enabled is true."
    }

    precondition {
      condition     = !var.create_image_pull_secret || trimspace(var.dockerhub_token) != ""
      error_message = "dockerhub_token must be set when create_image_pull_secret is true."
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

resource "kubernetes_secret_v1" "docker_hub_creds" {
  count = var.create_image_pull_secret ? 1 : 0

  metadata {
    name      = var.image_pull_secret_name
    namespace = kubernetes_namespace_v1.zipline_system.metadata[0].name
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "https://index.docker.io/v1/" = {
          username = var.dockerhub_username
          password = var.dockerhub_token
          auth     = base64encode("${var.dockerhub_username}:${var.dockerhub_token}")
        }
      }
    })
  }
}

module "addons" {
  source = "../../modules/zipline-kubernetes-addons"

  install_secrets_store_csi_driver = var.install_secrets_store_csi_driver
  install_cert_manager             = var.install_cert_manager
  install_flink_operator           = var.install_flink_operator
  install_opentelemetry_operator   = var.install_opentelemetry_operator
}

resource "helm_release" "secrets_store_csi_provider_aws" {
  count = var.install_aws_secrets_store_csi_provider ? 1 : 0

  name       = "secrets-store-csi-driver-provider-aws"
  repository = "https://aws.github.io/secrets-store-csi-driver-provider-aws"
  chart      = "secrets-store-csi-driver-provider-aws"
  namespace  = "kube-system"
  version    = "0.3.6"

  depends_on = [module.addons]
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
  source = "../../modules/zipline-orchestration-helm"

  namespace         = kubernetes_namespace_v1.zipline_system.metadata[0].name
  create_namespace  = false
  values            = local.values
  extra_values      = var.extra_values
  extra_values_yaml = var.extra_values_yaml

  depends_on = [
    terraform_data.configuration_validation,
    module.addons,
    helm_release.secrets_store_csi_provider_aws,
    helm_release.aws_load_balancer_controller,
    kubernetes_secret_v1.docker_hub_creds,
  ]
}
