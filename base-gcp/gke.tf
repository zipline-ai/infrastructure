# Enable additional APIs needed for GKE
resource "google_project_service" "container_api" {
  service                    = "container.googleapis.com"
  disable_dependent_services = false
  disable_on_destroy         = false
}


# GKE Autopilot Cluster
resource "google_container_cluster" "orchestration_cluster" {
  name     = "${var.customer_name}-zipline-cluster"
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

# Create namespace for orchestration components
resource "kubernetes_namespace" "zipline_system" {
  metadata {
    name = "zipline-system"

    labels = {
      name = "zipline-system"
    }
  }

  depends_on = [google_container_cluster.orchestration_cluster]
}

###########################################################

# Kubernetes Secrets for Database Credentials
resource "kubernetes_secret" "temporal_db_secret" {
  metadata {
    name      = "temporal-db-secret"
    namespace = kubernetes_namespace.zipline_system.metadata[0].name
  }

  data = {
    host     = google_sql_database_instance.temporal_instance.private_ip_address
    password = google_secret_manager_secret_version.db_password.secret_data
    username = google_sql_user.temporal_user.name
    database = google_sql_database.temporal_database.name
  }

  type = "Opaque"
}

resource "kubernetes_secret" "orchestration_db_secret" {
  metadata {
    name      = "orchestration-db-secret"
    namespace = kubernetes_namespace.zipline_system.metadata[0].name
  }

  data = {
    host     = google_sql_database_instance.orchestration_instance.private_ip_address
    password = google_secret_manager_secret_version.db_password.secret_data
    username = google_sql_user.orchestration_user.name
    database = google_sql_database.orchestration_database.name
  }

  type = "Opaque"
}

#############################################################

# Service Accounts and IAM Bindings

# Service Account for Temporal
resource "kubernetes_service_account" "temporal_sa" {
  metadata {
    name      = "temporal-sa"
    namespace = kubernetes_namespace.zipline_system.metadata[0].name

    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.temporal_gsa.email
    }
  }
}

# Google Service Account for Workload Identity
resource "google_service_account" "temporal_gsa" {
  account_id   = "temporal-sa"
  display_name = "Zipline Temporal Service Account"
  project      = data.google_project.zipline.project_id
}

# Bind Kubernetes SA to Google SA
resource "google_service_account_iam_binding" "temporal_workload_identity" {
  service_account_id = google_service_account.temporal_gsa.name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    "serviceAccount:${data.google_project.zipline.project_id}.svc.id.goog[${kubernetes_namespace.zipline_system.metadata[0].name}/${kubernetes_service_account.temporal_sa.metadata[0].name}]"
  ]
}

# Grant Cloud SQL access to the service account
resource "google_project_iam_member" "temporal_cloudsql" {
  project = data.google_project.zipline.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.temporal_gsa.email}"
}

# Service Account for Orchestration Hub and Worker
resource "google_service_account" "orchestration_sa" {
  account_id   = "orchestration-sa"
  display_name = "Zipline Orchestration Service Account"
  project      = data.google_project.zipline.project_id
}


resource "kubernetes_service_account" "orchestration_sa" {
  metadata {
    name      = "orchestration-sa"
    namespace = kubernetes_namespace.zipline_system.metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.orchestration_sa.email
    }
  }
}

resource "google_service_account_iam_member" "orchestration_workload_identity" {
  service_account_id = google_service_account.orchestration_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${data.google_project.zipline.project_id}.svc.id.goog[${kubernetes_namespace.zipline_system.metadata[0].name}/${kubernetes_service_account.orchestration_sa.metadata[0].name}]"
}

# Grant Cloud SQL access to the service account
resource "google_project_iam_member" "orchestration_cloudsql" {
  project = data.google_project.zipline.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.orchestration_sa.email}"
}

# Grant Bigtable access to the service account
resource "google_project_iam_member" "orchestration_bigtable" {
  project = data.google_project.zipline.project_id
  role    = "roles/bigtable.user"
  member  = "serviceAccount:${google_service_account.orchestration_sa.email}"
}

# Grant Dataproc access to the service account
resource "google_project_iam_member" "orchestration_dataproc" {
  project = data.google_project.zipline.project_id
  member  = "serviceAccount:${google_service_account.orchestration_sa.email}"
  role    = "roles/dataproc.editor"
}

# Grant Storage access to the service account
resource "google_project_iam_member" "orchestration_storage" {
  project = data.google_project.zipline.project_id
  member  = "serviceAccount:${google_service_account.orchestration_sa.email}"
  role    = "roles/storage.objectAdmin"
}

# Grant Monitoring access to the service account
resource "google_project_iam_member" "orchestration_monitoring" {
  project = data.google_project.zipline.project_id
  member  = "serviceAccount:${google_service_account.orchestration_sa.email}"
  role    = "roles/monitoring.editor"
}

###########################################################

#Deployments and Services for Temporal and Orchestration

# Temporal Server Deployment
resource "kubernetes_deployment" "temporal_server" {
  metadata {
    name      = "temporal-server"
    namespace = kubernetes_namespace.zipline_system.metadata[0].name
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
    google_sql_database.temporal_database,
    google_sql_user.temporal_user
  ]

  lifecycle {
    ignore_changes = [
      metadata,
      spec[0].template[0].metadata,
      spec[0].template[0].spec[0].container[0].resources[0].limits["ephemeral-storage"],
      spec[0].template[0].spec[0].container[0].resources[0].requests["ephemeral-storage"],
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
    namespace = kubernetes_namespace.zipline_system.metadata[0].name

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
    namespace = kubernetes_namespace.zipline_system.metadata[0].name

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
    namespace = kubernetes_namespace.zipline_system.metadata[0].name
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

    type = "ClusterIP"
  }

  depends_on = [kubernetes_deployment.temporal_web]

  lifecycle {
    ignore_changes = [metadata]
  }
}

resource "kubernetes_deployment" "temporal_worker" {
  metadata {
    name      = "orchestration-temporal-worker"
    namespace = kubernetes_namespace.zipline_system.metadata[0].name

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
          image = "ziplineai/orchestration-temporal-worker:v0.9.7"

          env {
            name  = "DB_URL"
            value = "jdbc:postgresql://${google_sql_database_instance.orchestration_instance.private_ip_address}:5432/${google_sql_database.orchestration_database.name}"
          }
          env {
            name  = "DB_USERNAME"
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
            value = google_bigtable_instance.zipline_bigtable_instance.name
          }
          env {
            name  = "CUSTOMER_ID"
            value = var.customer_name
          }
          env {
            name  = "ARTIFACT_PREFIX"
            value = var.artifact_prefix
          }
          env {
            name  = "TOPIC_ID"
            value = var.topic_id
          }
          env {
            name  = "TEMPORAL_SERVICE_ADDRESS"
            value = "${kubernetes_service.temporal_service.id}:7233"
          }
          env {
            name  = "TEMPORAL_NAMESPACE"
            value = "default"
          }
          env {
            name  = "TABLE_PARTITIONS_DATASET"
            value = "TABLE_PARTITIONS"
          }

          resources {
            limits = {
              cpu    = "4"
              memory = "4Gi"
            }
          }
        }
      }

    }
  }

  depends_on = [kubernetes_service.temporal_service,
    google_sql_database.orchestration_database,
    google_sql_user.orchestration_user,
    google_service_account_iam_member.orchestration_workload_identity,
    google_project_iam_member.orchestration_cloudsql,
    google_project_iam_member.orchestration_dataproc,
    google_project_iam_member.orchestration_bigtable,
    google_project_iam_member.orchestration_monitoring,
  google_project_iam_member.orchestration_storage]

  lifecycle {
    ignore_changes = [
      metadata,
      spec[0].template[0].spec[0].container[0].security_context,
      spec[0].template[0].spec[0].container[0].resources[0].limits["ephemeral-storage"],
      spec[0].template[0].spec[0].security_context,
      spec[0].template[0].spec[0].toleration,
      spec[0].template[0].spec[0].container[0].image
    ]
  }
}

resource "kubernetes_deployment" "orchestration_hub" {
  metadata {
    name      = "orchestration-hub"
    namespace = kubernetes_namespace.zipline_system.metadata[0].name

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
          image             = "ziplineai/orchestration-hub:v0.9.7"
          image_pull_policy = "Always"
          env {
            name  = "DB_URL"
            value = "jdbc:postgresql://${google_sql_database_instance.orchestration_instance.private_ip_address}:5432/${google_sql_database.orchestration_database.name}"
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
            value = google_bigtable_instance.zipline_bigtable_instance.name
          }
          env {
            name  = "CUSTOMER_ID"
            value = var.customer_name
          }
          env {
            name  = "ARTIFACT_PREFIX"
            value = var.artifact_prefix
          }
          env {
            name  = "TOPIC_ID"
            value = var.topic_id
          }
          env {
            name  = "TEMPORAL_SERVICE_ADDRESS"
            value = "${kubernetes_service.temporal_service.id}:7233"
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
            value = "TABLE_PARTITIONS"
          }
          port {
            container_port = 3903
          }
          resources {
            limits = {
              cpu    = "4"
              memory = "4Gi"
            }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_service.temporal_service,
    google_sql_database.orchestration_database,
    google_sql_user.orchestration_user,
    google_service_account_iam_member.orchestration_workload_identity,
    google_project_iam_member.orchestration_cloudsql,
    google_project_iam_member.orchestration_dataproc,
    google_project_iam_member.orchestration_bigtable,
    google_project_iam_member.orchestration_monitoring,
  google_project_iam_member.orchestration_storage]

  lifecycle {
    ignore_changes = [
      metadata,
      spec[0].template[0].metadata,
      spec[0].template[0].spec[0].container[0].security_context,
      spec[0].template[0].spec[0].container[0].resources[0].limits["ephemeral-storage"],
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
    namespace = kubernetes_namespace.zipline_system.metadata[0].name
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

    type = "ClusterIP"
  }

  depends_on = [kubernetes_deployment.orchestration_hub]

  lifecycle {
    ignore_changes = [metadata]
  }
}

# Deployment for Orchestration UI
resource "kubernetes_deployment" "orchestration_ui" {
  metadata {
    name      = "zipline-ui"
    namespace = kubernetes_namespace.zipline_system.metadata[0].name

    labels = {
      app = "zipline-ui"
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "zipline-ui"
      }
    }

    template {
      metadata {
        labels = {
          app = "zipline-ui"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.orchestration_sa.metadata[0].name
        container {
          name  = "web-ui"
          image = "ziplineai/web-ui:v0.9.7"

          env {
            name  = "API_BASE_URL"
            value = "https://${kubernetes_service.orchestration_hub_service.id}:3903"
          }

          env {
            name  = "DATABASE_URL"
            value = "postgres://${google_sql_user.orchestration_user.name}@${google_sql_database_instance.orchestration_instance.private_ip_address}:5432/${google_sql_database.orchestration_database.name}"
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

  depends_on = [kubernetes_service.orchestration_hub_service,
    google_sql_database.orchestration_database,
    google_sql_user.orchestration_user,
    google_service_account_iam_member.orchestration_workload_identity,
    google_project_iam_member.orchestration_cloudsql,
    google_project_iam_member.orchestration_dataproc,
    google_project_iam_member.orchestration_bigtable,
    google_project_iam_member.orchestration_monitoring,
    google_project_iam_member.orchestration_storage,
    kubernetes_ingress_v1.orchestration_hub_ingress]

  lifecycle {
    ignore_changes = [
      metadata,
      spec[0].template[0].spec[0].container[0].resources[0].limits["ephemeral-storage"],
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
    namespace = kubernetes_namespace.zipline_system.metadata[0].name
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

    type = "ClusterIP"
  }

  depends_on = [kubernetes_deployment.orchestration_ui]

  lifecycle {
    ignore_changes = [metadata]
  }
}

#################################################

# Configuration for HTTP(S) Load Balancers with Ingress

# Create a global static IP address
resource "google_compute_global_address" "orchestration_ui_ip" {
  name = "orchestration-ui-ip"
}

# Use a given domain for the Orchestration UI if provided
resource "kubernetes_manifest" "orchestration_ui_managed_cert_custom" {
  count = var.zipline_ui_domain != "" ? 1 : 0
  manifest = {
    apiVersion = "networking.gke.io/v1"
    kind       = "ManagedCertificate"
    metadata = {
      name      = "zipline-ui-ssl"
      namespace = kubernetes_namespace.zipline_system.metadata[0].name
    }
    spec = {
      domains = [var.zipline_ui_domain]
    }
  }
}

# Use ManagedCertificate CRD for nip.io domain
resource "kubernetes_manifest" "orchestration_ui_managed_cert_nip" {
  count = var.zipline_ui_domain != "" ? 0 : 1
  manifest = {
    apiVersion = "networking.gke.io/v1"
    kind       = "ManagedCertificate"
    metadata = {
      name      = "zipline-ui-ssl-nip"
      namespace = kubernetes_namespace.zipline_system.metadata[0].name
    }
    spec = {
      domains = ["${google_compute_global_address.orchestration_ui_ip.address}.nip.io"]
    }
  }
}

# Create the Ingress resource with Managed Certificate
resource "kubernetes_ingress_v1" "orchestration_ui_ingress" {
  metadata {
    name      = var.zipline_ui_domain != "" ? "orchestration-ui-ingress" : "orchestration-ui-ingress-nip"
    namespace = kubernetes_namespace.zipline_system.metadata[0].name

    annotations = {
      "kubernetes.io/ingress.global-static-ip-name" = google_compute_global_address.orchestration_ui_ip.name
      "networking.gke.io/managed-certificates"      = var.zipline_ui_domain != "" ? "zipline-ui-ssl" : "zipline-ui-ssl-nip"
      "kubernetes.io/ingress.class"                 = "gce"
    }
  }

  spec {
    rule {
      host = var.zipline_ui_domain != "" ? var.zipline_ui_domain : "${google_compute_global_address.orchestration_ui_ip.address}.nip.io"

      http {
        path {
          path      = "/*"
          path_type = "ImplementationSpecific"

          backend {
            service {
              name = kubernetes_service.orchestration_ui_service.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_service.orchestration_ui_service
  ]
}

# Output the static IP address and access information
output "orchestration_ui_ip" {
  value = google_compute_global_address.orchestration_ui_ip.address
  description = "Static IP address for the orchestration UI ingress"
}

output "orchestration_ui_https_url" {
  value = var.zipline_ui_domain != "" ? "https://${var.zipline_ui_domain}" : "https://${google_compute_global_address.orchestration_ui_ip.address}.nip.io"
  description = "HTTPS URL for the Zipline UI (This may take 15-60 minutes to be active)"
}

locals {
  orchestration_ui_custom_domain_instructions = <<-EOT
Zipline UI HTTPS Setup Instructions:

1. Point your domain's DNS A record to: ${google_compute_global_address.orchestration_ui_ip.address}
2. Wait 15-60 minutes for certificate provisioning
3. Access your service at: https://${var.zipline_ui_domain}

The Google-managed certificate will be automatically issued and renewed!
EOT

  orchestration_ui_nip_io_instructions = <<-EOT
Zipline UI HTTPS Setup Instructions (using nip.io):

1. Wait 15-60 minutes for certificate provisioning
2. Access your service at: https://${google_compute_global_address.orchestration_ui_ip.address}.nip.io
EOT
}

output "orchestration_ui_setup_instructions" {
  value = var.zipline_ui_domain != "" ? local.orchestration_ui_custom_domain_instructions : local.orchestration_ui_nip_io_instructions
}

# Create a global static IP address
resource "google_compute_global_address" "temporal_ui_ip" {
  name = "temporal-ui-ip"
}

# Use a given domain for the Temporal Web UI if provided
resource "kubernetes_manifest" "temporal_ui_managed_cert_custom" {
  count = var.temporal_domain != "" ? 1 : 0
  manifest = {
    apiVersion = "networking.gke.io/v1"
    kind       = "ManagedCertificate"
    metadata = {
      name      = "temporal-ui-ssl"
      namespace = kubernetes_namespace.zipline_system.metadata[0].name
    }
    spec = {
      domains = [var.temporal_domain]
    }
  }
}

# Use ManagedCertificate CRD for nip.io domain
resource "kubernetes_manifest" "temporal_ui_managed_cert_nip" {
  count = var.temporal_domain != "" ? 0 : 1
  manifest = {
    apiVersion = "networking.gke.io/v1"
    kind       = "ManagedCertificate"
    metadata = {
      name      = "temporal-ui-ssl-nip"  # Match the name from your debug output
      namespace = kubernetes_namespace.zipline_system.metadata[0].name
    }
    spec = {
      domains = ["${google_compute_global_address.temporal_ui_ip.address}.nip.io"]
    }
  }
}

# Ingress for nip.io
resource "kubernetes_ingress_v1" "temporal_ui_ingress" {
  metadata {
    name      = var.temporal_domain != "" ? "temporal-ui-ingress" : "temporal-ui-ingress-nip"
    namespace = kubernetes_namespace.zipline_system.metadata[0].name

    annotations = {
      "kubernetes.io/ingress.global-static-ip-name" = google_compute_global_address.temporal_ui_ip.name
      "networking.gke.io/managed-certificates"      = var.temporal_domain != "" ? "temporal-ui-ssl" : "temporal-ui-ssl-nip"
      "kubernetes.io/ingress.class"                 = "gce"

      # Redirect HTTP to HTTPS once certificate is ready
      "ingress.gcp.kubernetes.io/redirect-to-https" = "true"
    }
  }

  spec {
    rule {
      host = var.temporal_domain != "" ? var.temporal_domain : "${google_compute_global_address.temporal_ui_ip.address}.nip.io"

      http {
        path {
          path      = "/*"
          path_type = "ImplementationSpecific"

          backend {
            service {
              name = kubernetes_service.temporal_web_service.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_service.temporal_web_service
  ]
}


# Output the IP and instructions (like Cloud Run's domain mapping page)
output "temporal_ui_ip" {
  value = google_compute_global_address.temporal_ui_ip.address
  description = "Static IP address for the Temporal Web UI ingress"
}

output "temporal_ui_https_url" {
  value = var.temporal_domain != "" ? "https://${var.temporal_domain}" : "https://${google_compute_global_address.temporal_ui_ip.address}.nip.io"
  description = "HTTPS URL for the Temporal Web UI (This may take 15-60 minutes to be active)"
}


locals {
  temporal_ui_custom_domain_instructions = <<-EOT
Temporal UI HTTPS Setup Instructions:

1. Point your domain's DNS A record to: ${google_compute_global_address.orchestration_ui_ip.address}
2. Wait 15-60 minutes for certificate provisioning
3. Access your service at: https://${var.zipline_ui_domain}

The Google-managed certificate will be automatically issued and renewed!
EOT

  temporal_ui_nip_io_instructions = <<-EOT
Temporal UI HTTPS Setup Instructions (using nip.io):

1. Wait 15-60 minutes for certificate provisioning
2. Access your service at: https://${google_compute_global_address.orchestration_ui_ip.address}.nip.io
EOT
}

output "temporal_ui_setup_instructions" {
  value = var.temporal_domain != "" ? local.temporal_ui_custom_domain_instructions : local.temporal_ui_nip_io_instructions
}

# Create a global static IP address
resource "google_compute_global_address" "orchestration_hub_ip" {
  name = "orchestration-hub-ip"
}

# Use a given domain for the Temporal Hub if provided
resource "kubernetes_manifest" "orchestration_hub_managed_cert_custom" {
  count = var.hub_domain != "" ? 1 : 0
  manifest = {
    apiVersion = "networking.gke.io/v1"
    kind       = "ManagedCertificate"
    metadata = {
      name      = "orchestration-hub-ssl"
      namespace = kubernetes_namespace.zipline_system.metadata[0].name
    }
    spec = {
      domains = [var.hub_domain]
    }
  }
}

# Use ManagedCertificate CRD for nip.io domain
resource "kubernetes_manifest" "orchestration_hub_managed_cert_nip" {
  count = var.hub_domain != "" ? 0 : 1
  manifest = {
    apiVersion = "networking.gke.io/v1"
    kind       = "ManagedCertificate"
    metadata = {
      name      = "orchestration-hub-ssl-nip"  # Match the name from your debug output
      namespace = kubernetes_namespace.zipline_system.metadata[0].name
    }
    spec = {
      domains = ["${google_compute_global_address.orchestration_hub_ip.address}.nip.io"]
    }
  }
}

# Create the Ingress resource with Managed Certificate
resource "kubernetes_ingress_v1" "orchestration_hub_ingress" {
  metadata {
    name      = var.hub_domain != "" ? "orchestration-hub-ingress" : "orchestration-hub-ingress-nip"
    namespace = kubernetes_namespace.zipline_system.metadata[0].name

    annotations = {
      "kubernetes.io/ingress.global-static-ip-name" = google_compute_global_address.orchestration_ui_ip.name
      "networking.gke.io/managed-certificates"      = var.zipline_ui_domain != "" ? "orchestration-hub-ssl" : "orchestration-hub-ssl-nip"
      "kubernetes.io/ingress.class"                 = "gce"
    }
  }

  spec {
    rule {
      host = var.hub_domain != "" ? var.hub_domain : "${google_compute_global_address.orchestration_ui_ip.address}.nip.io"

      http {
        path {
          path      = "/*"
          path_type = "ImplementationSpecific"

          backend {
            service {
              name = kubernetes_service.orchestration_hub_service.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_service.orchestration_ui_service
  ]
}

# Output the static IP address and access information
output "orchestration_hub_ip" {
  value = google_compute_global_address.orchestration_hub_ip.address
  description = "Static IP address for the orchestration UI ingress"
}

output "orchestration_hub_https_url" {
  value = var.hub_domain != "" ? "https://${var.hub_domain}" : "https://${google_compute_global_address.orchestration_hub_ip.address}.nip.io"
  description = "HTTPS URL for the Zipline Hub (This may take 15-60 minutes to be active)"
}

locals {
  orchestration_hub_custom_domain_instructions = <<-EOT
Zipline UI HTTPS Setup Instructions:

1. Point your domain's DNS A record to: ${google_compute_global_address.orchestration_hub_ip.address}
2. Wait 15-60 minutes for certificate provisioning
3. Access your service at: https://${var.hub_domain}

The Google-managed certificate will be automatically issued and renewed!
EOT

  orchestration_hub_nip_io_instructions = <<-EOT
Zipline UI HTTPS Setup Instructions (using nip.io):

1. Wait 15-60 minutes for certificate provisioning
2. Access your service at: https://${google_compute_global_address.orchestration_hub_ip.address}.nip.io
EOT
}

output "orchestration_hub_setup_instructions" {
  value = var.hub_domain != "" ? local.orchestration_hub_custom_domain_instructions : local.orchestration_hub_nip_io_instructions
}
