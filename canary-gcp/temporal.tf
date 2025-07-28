# Enable additional APIs needed for GKE
resource "google_project_service" "container_api" {
  service = "container.googleapis.com"
  disable_dependent_services = false
  disable_on_destroy         = false
}

# GKE Autopilot Cluster
resource "google_container_cluster" "temporal_cluster" {
  name     = "temporal-cluster"
  location = var.region
  project  = data.google_project.zipline.project_id

  # Enable Autopilot
  enable_autopilot = true

  # Use existing VPC
  network    = google_compute_network.zipline_vpc.name
  subnetwork = google_compute_subnetwork.zipline_subnet.name

  # IP allocation for pods and services
  ip_allocation_policy {
    cluster_secondary_range_name  = "gke-pods"
    services_secondary_range_name = "gke-services"
  }

  # Private cluster configuration
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false  # Set to true if you want private endpoint
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  # Workload Identity for secure pod authentication
  workload_identity_config {
    workload_pool = "${data.google_project.zipline.project_id}.svc.id.goog"
  }

  depends_on = [
    google_project_service.container_api,
    google_service_networking_connection.private_vpc_connection
  ]
}

# Get cluster credentials for Kubernetes provider
data "google_client_config" "default" {}

data "google_container_cluster" "temporal_cluster" {
  name     = google_container_cluster.temporal_cluster.name
  location = google_container_cluster.temporal_cluster.location
  project  = data.google_project.zipline.project_id

  depends_on = [google_container_cluster.temporal_cluster]
}

# Configure Kubernetes provider
provider "kubernetes" {
  host                   = "https://${data.google_container_cluster.temporal_cluster.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(data.google_container_cluster.temporal_cluster.master_auth[0].cluster_ca_certificate)
}

# Create namespace for Temporal
resource "kubernetes_namespace" "temporal" {
  metadata {
    name = "temporal-system"

    labels = {
      name = "temporal-system"
    }
  }

  depends_on = [google_container_cluster.temporal_cluster]
}

resource "kubernetes_secret" "temporal_db_secret" {
  metadata {
    name      = "temporal-db-secret"
    namespace = kubernetes_namespace.temporal.metadata[0].name
  }

  data = {
    host     = google_sql_database_instance.temporal-instance.private_ip_address
    password = google_secret_manager_secret_version.db_password.secret_data
    username = "locker_user"
    database = "temporal"
  }

  type = "Opaque"
}

# Temporal Server Deployment
resource "kubernetes_deployment" "temporal_server" {
  metadata {
    name      = "temporal-server"
    namespace = kubernetes_namespace.temporal.metadata[0].name
    labels = {
      app = "temporal-server"
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "temporal-server"
      }
    }

    template {
      metadata {
        labels = {
          app = "temporal-server"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.temporal_sa.metadata[0].name

        container {
          name  = "temporal-server"
          image = "temporalio/auto-setup:1.28.0"

          env {
            name  = "DB"
            value = "postgres12"
          }
          env {
            name  = "DB_PORT"
            value = "5432"
          }
          env {
            name  = "POSTGRES_USER"
            value = google_sql_user.locker.name
          }
          env {
            name = "POSTGRES_PWD"
            value_from {
              secret_key_ref {
                name  = kubernetes_secret.temporal_db_secret.metadata[0].name
                key   = "password"
              }
            }
          }
          env {
            name  = "POSTGRES_SEEDS"
            value = google_sql_database_instance.temporal-instance.private_ip_address
          }
          env {
            name  = "DBNAME"
            value = google_sql_database.temporal_database.name
          }
          env {
            name  = "SKIP_DEFAULT_NAMESPACE_CREATION"
            value = "false"
          }

          env {
            name  = "SKIP_SCHEMA_SETUP"
            value = "false"
          }
          env {
            name  = "POSTGRES_CONNECT_TIMEOUT"
            value = "30"
          }

          env {
            name  = "LOG_LEVEL"
            value = "debug"
          }

          port {
            container_port = 7233
            name           = "grpc"
          }

          port {
            container_port = 8080
            name           = "http"
          }

          resources {
            requests = {
              cpu    = "1000m"
              memory = "2Gi"
            }
            limits = {
              cpu    = "2"
              memory = "4Gi"
            }
          }
        }
      }
    }
  }

  depends_on = [
    google_sql_database.temporal_database
  ]

  lifecycle {
    ignore_changes = [
      metadata,
      spec[0].template[0].spec[0].container[0].resources,
      spec[0].template[0].spec[0].container[0].security_context,
      spec[0].template[0].spec[0].security_context,
      spec[0].template[0].spec[0].toleration,
    ]
  }
}


# Service Account for Temporal
resource "kubernetes_service_account" "temporal_sa" {
  metadata {
    name      = "temporal-server"
    namespace = kubernetes_namespace.temporal.metadata[0].name

    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.temporal_gsa.email
    }
  }
}

# Google Service Account for Workload Identity
resource "google_service_account" "temporal_gsa" {
  account_id   = "temporal-server"
  display_name = "Temporal Server Service Account"
  project      = data.google_project.zipline.project_id
}

# Bind Kubernetes SA to Google SA
resource "google_service_account_iam_binding" "temporal_workload_identity" {
  service_account_id = google_service_account.temporal_gsa.name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    "serviceAccount:${data.google_project.zipline.project_id}.svc.id.goog[${kubernetes_namespace.temporal.metadata[0].name}/${kubernetes_service_account.temporal_sa.metadata[0].name}]"
  ]
}

# Grant Cloud SQL access to the service account
resource "google_project_iam_member" "temporal_cloudsql" {
  project = data.google_project.zipline.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.temporal_gsa.email}"
}

# LoadBalancer Service for Temporal Server
resource "kubernetes_service" "temporal_service" {
  metadata {
    name      = "temporal-service"
    namespace = kubernetes_namespace.temporal.metadata[0].name

    annotations = {
      "cloud.google.com/load-balancer-type" = "External"
    }
  }

  spec {
    selector = {
      app = "temporal-server"
    }

    port {
      name        = "grpc"
      port        = 7233
      target_port = 7233
      protocol    = "TCP"
    }

    port {
      name        = "http"
      port        = 8080
      target_port = 8080
      protocol    = "TCP"
    }

    type = "LoadBalancer"
  }

  depends_on = [kubernetes_deployment.temporal_server]
}

# Temporal Web UI Deployment
resource "kubernetes_deployment" "temporal_web" {
  metadata {
    name      = "temporal-web"
    namespace = kubernetes_namespace.temporal.metadata[0].name

    labels = {
      app = "temporal-web"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "temporal-web"
      }
    }

    template {
      metadata {
        labels = {
          app = "temporal-web"
        }
      }

      spec {
        container {
          name  = "temporal-web"
          image = "temporalio/ui:2.39.0"

          port {
            container_port = 8080
            name          = "http"
            protocol      = "TCP"
          }

          env {
            name  = "TEMPORAL_ADDRESS"
            value = "temporal-service:7233"
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }

          liveness_probe {
            http_get {
              path = "/"
              port = 8080
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 8080
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }
      }
    }
  }

  depends_on = [kubernetes_service.temporal_service]

    lifecycle {
        ignore_changes = [
          metadata,
          spec[0].template[0].spec[0].container[0].resources,
          spec[0].template[0].spec[0].container[0].security_context,
            spec[0].template[0].spec[0].security_context,
            spec[0].template[0].spec[0].toleration,
        ]
    }
}

# Service for Temporal Web UI
resource "kubernetes_service" "temporal_web_service" {
  metadata {
    name      = "temporal-web-service"
    namespace = kubernetes_namespace.temporal.metadata[0].name
  }

  spec {
    selector = {
      app = "temporal-web"
    }

    port {
      name        = "http"
      port        = 80
      target_port = 8080
      protocol    = "TCP"
    }

    type = "LoadBalancer"
  }

  depends_on = [kubernetes_deployment.temporal_web]
}
