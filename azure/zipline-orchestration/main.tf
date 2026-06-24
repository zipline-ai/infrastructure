resource "kubernetes_namespace_v1" "zipline_system" {
  metadata {
    name        = var.namespace
    labels      = var.namespace_labels
    annotations = var.namespace_annotations
  }
}

resource "terraform_data" "configuration_validation" {
  input = {
    create_image_pull_secret = var.create_image_pull_secret
  }

  lifecycle {
    precondition {
      condition     = !var.create_image_pull_secret || trimspace(var.dockerhub_token) != ""
      error_message = "dockerhub_token must be set when create_image_pull_secret is true."
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

module "zipline_orchestration" {
  source = "../../modules/zipline-orchestration"

  release_name      = var.release_name
  namespace         = kubernetes_namespace_v1.zipline_system.metadata[0].name
  create_namespace  = false
  values            = local.values
  extra_values      = var.extra_values
  extra_values_yaml = var.extra_values_yaml
  wait              = var.helm_wait
  timeout           = var.helm_timeout

  depends_on = [
    terraform_data.configuration_validation,
    module.addons,
    kubernetes_secret_v1.docker_hub_creds,
  ]
}
