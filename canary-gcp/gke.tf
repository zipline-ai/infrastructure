# Enable additional APIs needed for GKE
resource "google_project_service" "container_api" {
  service                    = "container.googleapis.com"
  disable_dependent_services = false
  disable_on_destroy         = false
}

# GKE Autopilot Cluster
resource "google_container_cluster" "orchestration_cluster" {
  name     = "orchestration-cluster"
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
    enable_private_endpoint = false # Set to true if you want private endpoint
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  # Workload Identity for secure pod authentication
  workload_identity_config {
    workload_pool = "${data.google_project.zipline.project_id}.svc.id.goog"
  }

  dns_config {
    cluster_dns        = "CLOUD_DNS"
    cluster_dns_scope  = "CLUSTER_SCOPE"
    cluster_dns_domain = "cluster.local"
  }

  depends_on = [
    google_project_service.container_api,
    google_service_networking_connection.private_vpc_connection
  ]
}

#Get cluster credentials for Kubernetes provider
data "google_client_config" "default" {}

data "google_container_cluster" "orchestration_cluster" {
  name     = google_container_cluster.orchestration_cluster.name
  location = var.region
  project  = data.google_project.zipline.project_id

  depends_on = [google_container_cluster.orchestration_cluster]
}

# Configure Kubernetes provider
provider "kubernetes" {
  host                   = "https://${data.google_container_cluster.orchestration_cluster.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(data.google_container_cluster.orchestration_cluster.master_auth[0].cluster_ca_certificate)
}

# Create namespace for Temporal
resource "kubernetes_namespace" "orchestration" {
  metadata {
    name = "orchestration-system"

    labels = {
      name = "orchestration-system"
    }
  }

  depends_on = [google_container_cluster.orchestration_cluster]
}

resource "kubernetes_secret" "temporal_db_secret" {
  metadata {
    name      = "temporal-db-secret"
    namespace = kubernetes_namespace.orchestration.metadata[0].name
  }

  data = {
    host     = google_sql_database_instance.temporal_gke_instance.private_ip_address
    password = google_secret_manager_secret_version.db_password.secret_data
    username = google_sql_user.temporal_gke_locker.name
    database = google_sql_database.temporal_gke_database.name
  }

  type = "Opaque"
}

resource "kubernetes_secret" "orchestration_db_secret" {
  metadata {
    name      = "orchestration-db-secret"
    namespace = kubernetes_namespace.orchestration.metadata[0].name
  }

  data = {
    host     = google_sql_database_instance.orchestration_gke_instance.private_ip_address
    password = google_secret_manager_secret_version.db_password.secret_data
    username = google_sql_user.orchestration_gke_locker.name
    database = google_sql_database.orchestration_gke_database.name
  }

  type = "Opaque"
}

# Service Account for Temporal
resource "kubernetes_service_account" "temporal_sa" {
  metadata {
    name      = "temporal-server"
    namespace = kubernetes_namespace.orchestration.metadata[0].name

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
    "serviceAccount:${data.google_project.zipline.project_id}.svc.id.goog[${kubernetes_namespace.orchestration.metadata[0].name}/${kubernetes_service_account.temporal_sa.metadata[0].name}]"
  ]
}

# Grant Cloud SQL access to the service account
resource "google_project_iam_member" "temporal_cloudsql" {
  project = data.google_project.zipline.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.temporal_gsa.email}"
}

# Service Account for Orchestration Hub and Worker
resource "google_service_account" "orchestration_gke_sa" {
  account_id   = "orchestration-gke-sa"
  display_name = "Orchestration Service Account"
  project      = data.google_project.zipline.project_id
}


resource "kubernetes_service_account" "orchestration_sa" {
  metadata {
    name      = "orchestration-gke-sa"
    namespace = kubernetes_namespace.orchestration.metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.orchestration_gke_sa.email
    }
  }
}

resource "google_service_account_iam_member" "orchestration_workload_identity" {
  service_account_id = google_service_account.orchestration_gke_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${data.google_project.zipline.project_id}.svc.id.goog[${kubernetes_namespace.orchestration.metadata[0].name}/orchestration-gke-sa]"
}

# Grant Cloud SQL access to the service account
resource "google_project_iam_member" "orchestration_gke_cloudsql" {
  project = data.google_project.zipline.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.orchestration_gke_sa.email}"
}

# Grant Bigtable access to the service account
resource "google_project_iam_member" "orchestration_gke_bigtable" {
  project = data.google_project.zipline.project_id
  role    = "roles/bigtable.user"
  member  = "serviceAccount:${google_service_account.orchestration_gke_sa.email}"
}

# Grant Dataproc access to the service account
resource "google_project_iam_member" "orchestration_gke_dataproc" {
  project = data.google_project.zipline.project_id
  member  = "serviceAccount:${google_service_account.orchestration_gke_sa.email}"
  role    = "roles/dataproc.editor"
}

# Grant Storage access to the service account
resource "google_project_iam_member" "orchestration_gke_storage" {
  project = data.google_project.zipline.project_id
  member  = "serviceAccount:${google_service_account.orchestration_gke_sa.email}"
  role    = "roles/storage.objectAdmin"
}

# Grant Monitoring access to the service account
resource "google_project_iam_member" "orchestration_gke_monitoring" {
  project = data.google_project.zipline.project_id
  member  = "serviceAccount:${google_service_account.orchestration_gke_sa.email}"
  role    = "roles/monitoring.editor"
}

# Temporal Server Deployment
resource "kubernetes_deployment" "temporal_server" {
  metadata {
    name      = "temporal-server"
    namespace = kubernetes_namespace.orchestration.metadata[0].name
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
            name = "POSTGRES_USER"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.temporal_db_secret.metadata[0].name
                key  = "username"
              }
            }
          }
          env {
            name = "POSTGRES_PWD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.temporal_db_secret.metadata[0].name
                key  = "password"
              }
            }
          }
          env {
            name = "POSTGRES_SEEDS"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.temporal_db_secret.metadata[0].name
                key  = "host"
              }
            }
          }
          env {
            name = "DBNAME"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.temporal_db_secret.metadata[0].name
                key  = "database"
              }
            }
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
    google_service_account_iam_member.orchestration_workload_identity,
    google_sql_database.temporal_gke_database,
    google_sql_user.temporal_gke_locker
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

# LoadBalancer Service for Temporal Server
resource "kubernetes_service" "temporal_service" {
  metadata {
    name      = "temporal-service"
    namespace = kubernetes_namespace.orchestration.metadata[0].name

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

  }

  depends_on = [kubernetes_deployment.temporal_server]

  lifecycle {
    ignore_changes = [metadata]
  }
}

# Temporal Web UI Deployment
resource "kubernetes_deployment" "temporal_web" {
  metadata {
    name      = "temporal-web"
    namespace = kubernetes_namespace.orchestration.metadata[0].name

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
            name           = "http"
            protocol       = "TCP"
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
    namespace = kubernetes_namespace.orchestration.metadata[0].name
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

  lifecycle {
    ignore_changes = [metadata]
  }
}

resource "kubernetes_deployment" "temporal_worker" {
  metadata {
    name      = "orchestration-temporal-worker"
    namespace = kubernetes_namespace.orchestration.metadata[0].name

    labels = {
      app = "orchestration-temporal-worker"
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "orchestration-temporal-worker"
      }
    }

    template {
      metadata {
        labels = {
          app = "orchestration-temporal-worker"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.orchestration_sa.metadata[0].name
        container {
          name  = "orchestration-temporal-worker"
          image = "ziplineai/orchestration-temporal-worker:v0.9.8"

          env {
            name  = "DB_URL"
            value = "jdbc:postgresql://${google_sql_database_instance.orchestration_gke_instance.private_ip_address}:5432/${google_sql_database.orchestration_gke_database.name}"
          }
          env {
            name  = "DB_USERNAME"
            value = google_sql_user.locker.name
          }
          env {
            name = "DB_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.temporal_db_secret.metadata[0].name
                key  = "password"
              }
            }
          }
          env {
            name  = "GCP_REGION"
            value = var.region
          }
          env {
            name  = "GCP_PROJECT_ID"
            value = data.google_project.zipline.project_id
          }
          env {
            name  = "GCP_BIGTABLE_INSTANCE_ID"
            value = module.base_setup.bigtable_instance_name
          }
          env {
            name  = "CUSTOMER_ID"
            value = var.name
          }
          env {
            name  = "ARTIFACT_PREFIX"
            value = "gs://zipline-artifacts-${var.name}"
          }
          env {
            name  = "TOPIC_ID"
            value = "canary-testing"
          }
          env {
            name  = "TEMPORAL_SERVICE_ADDRESS"
            value = "temporal-service:7233"
          }
          env {
            name  = "TEMPORAL_NAMESPACE"
            value = "default"
          }
          env {
            name  = "TABLE_PARTITIONS_DATASET"
            value = "TABLE_PARTITIONS_DEV"
          }

          resources {
            limits = {
              cpu    = "16"
              memory = "64Gi"
            }
          }
        }
      }

    }
  }

  depends_on = [kubernetes_service.temporal_service,
    google_sql_database.orchestration_gke_database,
    google_sql_user.locker,
    google_service_account_iam_member.orchestration_workload_identity,
    google_project_iam_member.orchestration_gke_cloudsql,
    google_project_iam_member.orchestration_gke_dataproc,
    google_project_iam_member.orchestration_gke_bigtable,
    google_project_iam_member.orchestration_gke_monitoring,
  google_project_iam_member.orchestration_gke_storage]

  lifecycle {
    ignore_changes = [
      metadata,
      spec[0].template[0].spec[0].container[0].resources,
      spec[0].template[0].spec[0].container[0].security_context,
      spec[0].template[0].spec[0].security_context,
      spec[0].template[0].spec[0].toleration,
      spec[0].template[0].spec[0].container[0].image
    ]
  }
}

resource "kubernetes_deployment" "orchestration_hub" {
  metadata {
    name      = "orchestration-hub"
    namespace = kubernetes_namespace.orchestration.metadata[0].name

    labels = {
      app = "orchestration-hub"
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "orchestration-hub"
      }
    }

    template {
      metadata {
        labels = {
          app = "orchestration-hub"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.orchestration_sa.metadata[0].name
        container {
          name              = "orchestration-hub"
          image             = "ziplineai/orchestration-hub:v0.9.8"
          image_pull_policy = "Always"
          env {
            name  = "DB_URL"
            value = "jdbc:postgresql://${google_sql_database_instance.orchestration_gke_instance.private_ip_address}:5432/${google_sql_database.orchestration_gke_database.name}"
          }
          env {
            name = "DB_USERNAME"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.orchestration_db_secret.metadata[0].name
                key  = "username"
              }
            }
          }
          env {
            name = "DB_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.orchestration_db_secret.metadata[0].name
                key  = "password"
              }
            }
          }
          env {
            name  = "GCP_REGION"
            value = var.region
          }
          env {
            name  = "GCP_PROJECT_ID"
            value = data.google_project.zipline.project_id
          }
          env {
            name  = "GCP_BIGTABLE_INSTANCE_ID"
            value = module.base_setup.bigtable_instance_name
          }
          env {
            name  = "CUSTOMER_ID"
            value = var.name
          }
          env {
            name  = "ARTIFACT_PREFIX"
            value = "gs://zipline-artifacts-${var.name}"
          }
          env {
            name  = "TOPIC_ID"
            value = "canary-testing"
          }
          env {
            name  = "TEMPORAL_SERVICE_ADDRESS"
            value = "temporal-service:7233"
          }
          env {
            name  = "TEMPORAL_NAMESPACE"
            value = "default"
          }
          env {
            name  = "ORCHESTRATION_PORT"
            value = 3903
          }
          env {
            name  = "TABLE_PARTITIONS_DATASET"
            value = "TABLE_PARTITIONS_DEV"
          }
          port {
            container_port = 3903
          }
          resources {
            limits = {
              cpu    = "16"
              memory = "64Gi"
            }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_service.temporal_service,
    google_sql_database.orchestration_gke_database,
    google_sql_user.locker,
    google_service_account_iam_member.orchestration_workload_identity,
    google_project_iam_member.orchestration_gke_cloudsql,
    google_project_iam_member.orchestration_gke_dataproc,
    google_project_iam_member.orchestration_gke_bigtable,
    google_project_iam_member.orchestration_gke_monitoring,
  google_project_iam_member.orchestration_gke_storage]

  lifecycle {
    ignore_changes = [
      metadata,
      spec[0].template[0].spec[0].container[0].resources,
      spec[0].template[0].spec[0].container[0].security_context,
      spec[0].template[0].spec[0].security_context,
      spec[0].template[0].spec[0].toleration,
      spec[0].template[0].spec[0].container[0].image
    ]
  }
}

# Service for Orchestration Hub
resource "kubernetes_service" "orchestration_hub_service" {
  metadata {
    name      = "orchestration-hub-service"
    namespace = kubernetes_namespace.orchestration.metadata[0].name
  }

  spec {
    selector = {
      app = "orchestration-hub"
    }

    port {
      name        = "http"
      port        = 3903
      target_port = 3903
      protocol    = "TCP"
    }

    type = "LoadBalancer"
  }

  depends_on = [kubernetes_deployment.orchestration_hub]

  lifecycle {
    ignore_changes = [metadata]
  }
}

# Deployment for Orchestration UI
resource "kubernetes_deployment" "orchestration_ui" {
  metadata {
    name      = "orchestration-ui"
    namespace = kubernetes_namespace.orchestration.metadata[0].name

    labels = {
      app = "orchestration-ui"
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "orchestration-ui"
      }
    }

    template {
      metadata {
        labels = {
          app = "orchestration-ui"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.orchestration_sa.metadata[0].name
        container {
          name  = "web-ui"
          image = "ziplineai/web-ui:v0.9.8"

          env {
            name  = "API_BASE_URL"
            value = "http://orchestration-hub-service:3903"
          }

          env {
            name  = "DATABASE_URL"
            value = "postgres://${google_sql_user.orchestration_gke_locker.name}@${google_sql_database_instance.orchestration_gke_instance.private_ip_address}:5432/${google_sql_database.orchestration_gke_database.name}"
          }
          env {
            name = "PGPASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.orchestration_db_secret.metadata[0].name
                key  = "password"
              }
            }
          }

          resources {
            limits = {
              cpu    = "1000m"
              memory = "1Gi"
            }
          }
          port {
            container_port = 3000
          }
        }
      }
    }
  }

  depends_on = [kubernetes_service.orchestration_hub_service, kubernetes_deployment.temporal_worker]

  lifecycle {
    ignore_changes = [
      metadata,
      spec[0].template[0].spec[0].container[0].resources,
      spec[0].template[0].spec[0].container[0].security_context,
      spec[0].template[0].spec[0].security_context,
      spec[0].template[0].spec[0].toleration,
      spec[0].template[0].spec[0].container[0].image

    ]
  }
}

# Service for Orchestration UI
resource "kubernetes_service" "orchestration_ui_service" {
  metadata {
    name      = "orchestration-ui-service"
    namespace = kubernetes_namespace.orchestration.metadata[0].name
  }

  spec {
    selector = {
      app = "orchestration-ui"
    }

    port {
      name        = "http"
      port        = 80
      target_port = 3000
      protocol    = "TCP"
    }

    type = "LoadBalancer"
  }

  depends_on = [kubernetes_deployment.orchestration_ui]

  lifecycle {
    ignore_changes = [metadata]
  }
}