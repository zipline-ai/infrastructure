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
                    image = "${aws_ecr_repository.frontend.repository_url}:latest"
                    name = "frontend"

                    env {
                        name = "API_BASE_URL"
                        value = "http://${kubernetes_service.app.status.0.load_balancer.0.ingress.0.hostname}:9000"
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
            port = 3000
            target_port = 3000
        }
        selector = {
            service = "frontend"
        }
        type = "LoadBalancer"
    }

}