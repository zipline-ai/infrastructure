// Deploys the frontend on Kubernetes with a loadbalancer so it is accessible.
data "aws_ecr_repository" "frontend" {
    name = "zipline-ai/canary-frontend"
}

resource "kubernetes_deployment" "frontend" {
    metadata {
        name = "frontend"
        labels = {
            service = "frontend"
        }
    }

    spec {
        replicas = 1

        selector {
            match_labels = {
                service = "frontend"
            }
        }

        template {
            metadata {
                labels = {
                    service = "frontend"
                }
            }

            spec {
                container {
                    image = "${data.aws_ecr_repository.frontend.repository_url}:canary"
                    image_pull_policy = "Always"
                    name = "frontend"

                    env {
                        name = "API_BASE_URL"
                        value = "http://${kubernetes_service.app.spec[0].cluster_ip}:9000"
                    }

                    port {
                        container_port = 3000
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
    depends_on = [ kubernetes_service.app ]
}

resource "kubernetes_service" "frontend" {
    metadata {
        name = "frontend"
        labels = {
            service = "frontend"
        }
    }

    spec {
        port {
            name = "3000"
            port = 3000
            target_port = 3000
        }
        selector = {
            service = "frontend"
        }
        type = "LoadBalancer"
    }

}

data "kubernetes_service" "app" {
    metadata {
        name = "app"
    }
}