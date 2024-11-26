// Deploys the app on Kubernetes with a service for the frontend to find.
resource "kubernetes_deployment" "app" {
  metadata {
    name = "app"
    labels = {
      service = "app"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        service = "app"
      }
    }

    template {
      metadata {
        labels = {
          service = "app"
        }
      }

      spec {
        container {
          image = "${data.aws_ecr_repository.app.repository_url}:canary"
          image_pull_policy = "Always"
          name = "app"

          env {
            name = "AWS_DEFAULT_REGION"
            value = var.region
          }
          env {
            name = "JAVA_OPTS"
            value = "-Xms1g -Xmx1g"
          }
          env {
            name = "PLAY_HTTP_SECRET_KEY"
            value = "my_fake_chronon_monitoring_hub_http_secret_key"
          }

          port {
            container_port = 9000
            protocol = "TCP"
          }
        }
        restart_policy = "Always"
      }
    }

  }
  lifecycle {
    ignore_changes = [
      spec[0].template[0].metadata[0].annotations["kubectl.kubernetes.io/restartedAt"],
    ]
  }

  depends_on = [ aws_eks_node_group.arm_spot_node_group, aws_eks_addon.coredns ]
}

resource "kubernetes_service" "app" {
  metadata {
    name = "app"
    labels = {
      service = "app"
    }
  }

  spec {
    port {
      name = "9000"
      port = 9000
      target_port = 9000
    }
    selector = {
      service = "app"
    }
  }

}