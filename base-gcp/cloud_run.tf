# Google Artifact Registry - Remote Repository for Docker Hub
resource "google_artifact_registry_repository" "docker_hub_remote_repository" {
  format        = "DOCKER"
  repository_id = "${var.customer_name}-zipline-docker-hub-proxy"
  location      = var.region
  description   = "Remote repository for Docker images from Docker Hub"
  mode          = "REMOTE_REPOSITORY"
  remote_repository_config {
    description = "Proxy repository for ziplineai images on Docker Hub"
    docker_repository {
      public_repository = "DOCKER_HUB"
    }
  }
}

# Enable required APIs
resource "google_project_service" "cloudrun_api" {
  project = data.google_project.zipline.project_id
  service = "run.googleapis.com"

  disable_dependent_services = false
  disable_on_destroy         = false
}

resource "google_project_service" "iap_api" {
  service = "iap.googleapis.com"

  disable_dependent_services = false
  disable_on_destroy         = false
}

##############################################################
# Service Accounts and IAM Roles

# Service Account for Orchestration
resource "google_service_account" "orchestration_service_account" {
  account_id   = "zipline-orchestration-sa"
  display_name = "Zipline Cloud Run Service Account"
  project      = data.google_project.zipline.project_id
}

resource "google_project_iam_member" "orchestration_service_account_dataproc" {
  project = data.google_project.zipline.project_id
  member  = "serviceAccount:${google_service_account.orchestration_service_account.email}"
  role    = "roles/dataproc.editor"
}

resource "google_project_iam_member" "orchestration_service_account_storage" {
  project = data.google_project.zipline.project_id
  member  = "serviceAccount:${google_service_account.orchestration_service_account.email}"
  role    = "roles/storage.objectAdmin"
}

resource "google_project_iam_member" "orchestration_service_account_cloudsql" {
  project = data.google_project.zipline.project_id
  member  = "serviceAccount:${google_service_account.orchestration_service_account.email}"
  role    = "roles/cloudsql.client"
}

resource "google_project_iam_member" "orchestration_service_account_bigtable" {
  project = data.google_project.zipline.project_id
  member  = "serviceAccount:${google_service_account.orchestration_service_account.email}"
  role    = "roles/bigtable.user"
}

resource "google_project_iam_member" "orchestration_service_account_secretmanager" {
  project = data.google_project.zipline.project_id
  member  = "serviceAccount:${google_service_account.orchestration_service_account.email}"
  role    = "roles/secretmanager.secretAccessor"
}

# Service Account for Temporal Server
resource "google_service_account" "temporal_service_account" {
  account_id   = "zipline-temporal-sa"
  display_name = "Zipline Cloud Run Service Account"
  project      = data.google_project.zipline.project_id
}

resource "google_project_iam_member" "temporal_service_account_secretmanager" {
  project = data.google_project.zipline.project_id
  member  = "serviceAccount:${google_service_account.temporal_service_account.email}"
  role    = "roles/secretmanager.secretAccessor"
}

resource "google_project_iam_member" "temporal_service_account_cloudsql" {
  project = data.google_project.zipline.project_id
  member  = "serviceAccount:${google_service_account.temporal_service_account.email}"
  role    = "roles/cloudsql.client"
}

################################################################
# Cloud Run v2 service for Temporal Server

resource "google_cloud_run_v2_service" "temporal_server" {
  name     = "${var.customer_name}-zipline-temporal-server"
  location = var.region
  project  = data.google_project.zipline.project_id

  ingress = "INGRESS_TRAFFIC_ALL"

  template {

    vpc_access {
      network_interfaces {
        network    = google_compute_network.zipline_vpc.name
        subnetwork = google_compute_subnetwork.zipline_subnet.name
      }
    }

    service_account = google_service_account.temporal_service_account.email
    containers {
      image = "${google_artifact_registry_repository.docker_hub_remote_repository.location}-docker.pkg.dev/${data.google_project.zipline.project_id}/${google_artifact_registry_repository.docker_hub_remote_repository.repository_id}/temporalio/auto-setup:1.28.0"
      name  = "temporal-server"

      ports {
        name           = "h2c"
        container_port = 7233
      }

      # Environment variables for PostgreSQL connection
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
        value = google_sql_user.temporal_user.name
      }
      env {
        name = "POSTGRES_PWD"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.db_password.secret_id
            version = "latest"
          }
        }
      }
      env {
        name  = "POSTGRES_SEEDS"
        value = google_sql_database_instance.temporal_instance.private_ip_address
      }
      env {
        name  = "DBNAME"
        value = google_sql_database.temporal_database.name
      }
      env {
        name  = "SKIP_DEFAULT_NAMESPACE_CREATION"
        value = "false"
      }
      # Add additional environment variables for better debugging
      env {
        name  = "LOG_LEVEL"
        value = "warn"
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
        name  = "BIND_ON_IP"
        value = "0.0.0.0"
      }

      resources {
        limits = {
          cpu    = "2"
          memory = "2Gi"
        }
      }

      startup_probe {
        tcp_socket {
          port = 7233
        }
        initial_delay_seconds = 30
        period_seconds        = 10
        timeout_seconds       = 5
        failure_threshold     = 10
      }

    }

  }

  depends_on = [
    google_project_service.cloudrun_api,
    google_sql_database_instance.temporal_instance,
    google_service_account.temporal_service_account,
    google_project_iam_member.temporal_service_account_cloudsql,
    google_project_iam_member.temporal_service_account_secretmanager,
  ]
}

resource "google_cloud_run_v2_service_iam_member" "temporal_ui_server_access" {
  location = google_cloud_run_v2_service.temporal_server.location
  project  = google_cloud_run_v2_service.temporal_server.project
  name     = google_cloud_run_v2_service.temporal_server.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.temporal_service_account.email}"
}

resource "google_cloud_run_v2_service_iam_member" "orchestration_temporal_server_access" {
  location = google_cloud_run_v2_service.temporal_server.location
  project  = google_cloud_run_v2_service.temporal_server.project
  name     = google_cloud_run_v2_service.temporal_server.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.orchestration_service_account.email}"
}

resource "google_cloud_run_v2_service_iam_member" "temporal_server_unauthenticated" {
  location = google_cloud_run_v2_service.temporal_server.location
  project  = google_cloud_run_v2_service.temporal_server.project
  name     = google_cloud_run_v2_service.temporal_server.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

################################################################
# Cloud Run v2 service for Temporal UI

resource "google_cloud_run_v2_service" "temporal_ui" {
  name     = "${var.customer_name}-zipline-temporal-ui"
  location = var.region
  project  = data.google_project.zipline.project_id

  template {

    vpc_access {
      network_interfaces {
        network    = google_compute_network.zipline_vpc.name
        subnetwork = google_compute_subnetwork.zipline_subnet.name
      }
      egress = "ALL_TRAFFIC"
    }

    service_account = google_service_account.temporal_service_account.email

    containers {
      image = "${google_artifact_registry_repository.docker_hub_remote_repository.location}-docker.pkg.dev/${data.google_project.zipline.project_id}/${google_artifact_registry_repository.docker_hub_remote_repository.repository_id}/temporalio/ui:2.39.0"
      name  = "temporal-ui"

      ports {
        name           = "http1"
        container_port = 8080
      }

      # Environment variables for PostgreSQL connection
      env {
        name  = "TEMPORAL_ADDRESS"
        value = "${replace(google_cloud_run_v2_service.temporal_server.uri, "https://", "")}:443"
      }
      env {
        name  = "TEMPORAL_TLS_ENABLE_HOST_VERIFICATION"
        value = "false"
      }

      env {
        name  = "TEMPORAL_TLS_SERVER_NAME"
        value = replace(google_cloud_run_v2_service.temporal_server.uri, "https://", "")
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }

      startup_probe {
        http_get {
          path = "/"
          port = 8080
        }
        initial_delay_seconds = 10
        period_seconds        = 5
        timeout_seconds       = 3
        failure_threshold     = 5
      }

    }

  }
}

# IAM policy to allow unauthenticated access (adjust as needed)
resource "google_cloud_run_v2_service_iam_member" "temporal_ui_public_access" {
  location = google_cloud_run_v2_service.temporal_ui.location
  project  = google_cloud_run_v2_service.temporal_ui.project
  name     = google_cloud_run_v2_service.temporal_ui.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

################################################################
# Cloud Run v2 Worker Pool for Orchestration Temporal Worker

resource "google_cloud_run_v2_worker_pool" "orchestration_temporal_worker" {
  location     = var.region
  name         = "${var.customer_name}-zipline-orchestration-worker"
  project      = data.google_project.zipline.project_id
  launch_stage = "BETA"

  template {

    vpc_access {
      network_interfaces {
        network    = google_compute_network.zipline_vpc.name
        subnetwork = google_compute_subnetwork.zipline_subnet.name
      }
      egress = "ALL_TRAFFIC"
    }


    service_account = google_service_account.orchestration_service_account.email
    containers {
      image = "${google_artifact_registry_repository.docker_hub_remote_repository.location}-docker.pkg.dev/${data.google_project.zipline.project_id}/${google_artifact_registry_repository.docker_hub_remote_repository.repository_id}/ziplineai/orchestration-temporal-worker:4d58aeed22d262ed1a7f00532aa3c388eba5cd6c"
      name  = "orchestration-worker"

      env {
        name  = "DB_URL"
        value = "jdbc:postgresql://${google_sql_database_instance.orchestration_instance.private_ip_address}:5432/${google_sql_database.orchestration_database.name}"
      }
      env {
        name  = "DB_USERNAME"
        value = google_sql_user.orchestration_user.name
      }
      env {
        name = "DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.db_password.secret_id
            version = "latest"
          }
        }
      }
      env {
        name  = "TEMPORAL_SERVICE_ADDRESS"
        value = "${replace(google_cloud_run_v2_service.temporal_server.uri, "https://", "")}:443"
      }
      env {
        name  = "TEMPORAL_NAMESPACE"
        value = "default"
      }
      env {
        name  = "GCP_PROJECT_ID"
        value = data.google_project.zipline.project_id
      }
      env {
        name  = "GCP_REGION"
        value = var.region
      }
      env {
        name  = "GCP_BIGTABLE_INSTANCE_ID"
        value = google_bigtable_instance.zipline_bigtable_instance.name
      }
      env {
        name  = "ZIPLINE_LOGS_BUCKET_NAME"
        value = google_storage_bucket.zipline-logs.name
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
        name  = "TABLE_PARTITIONS_DATASET"
        value = "TABLE_PARTITIONS"
      }
      env {
        name  = "BIGTABLE_INITIAL_RPC_TIMEOUT_DURATION"
        value = "PT0.5S"
      }

      env {
        name  = "BIGTABLE_MAX_RPC_TIMEOUT_DURATION"
        value = "PT0.5S"
      }
      env {
        name  = "USE_HTTPS"
        value = "true"
      }

      resources {
        limits = {
          cpu    = "2"
          memory = "4Gi"
        }
      }
    }
  }
}

################################################################
# Cloud Run v2 service for Orchestration Hub

resource "google_cloud_run_v2_service" "orchestration" {
  name     = "${var.customer_name}-zipline-orchestration"
  location = var.region

  template {

    vpc_access {
      network_interfaces {
        network    = google_compute_network.zipline_vpc.name
        subnetwork = google_compute_subnetwork.zipline_subnet.name
      }
      egress = "ALL_TRAFFIC"
    }
    # Main orchestration container
    containers {
      name  = "orchestration-hub"
      image = "${google_artifact_registry_repository.docker_hub_remote_repository.location}-docker.pkg.dev/${data.google_project.zipline.project_id}/${google_artifact_registry_repository.docker_hub_remote_repository.repository_id}/ziplineai/orchestration-hub:4d58aeed22d262ed1a7f00532aa3c388eba5cd6c"
      env {
        name  = "DB_URL"
        value = "jdbc:postgresql://${google_sql_database_instance.orchestration_instance.private_ip_address}:5432/${google_sql_database.orchestration_database.name}"
      }
      env {
        name  = "DB_USERNAME"
        value = google_sql_user.orchestration_user.name
      }
      env {
        name = "DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.db_password.secret_id
            version = "latest"
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
        name  = "TEMPORAL_SERVICE_ADDRESS"
        value = "${replace(google_cloud_run_v2_service.temporal_server.uri, "https://", "")}:443"
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
        value = "TABLE_PARTITIONS_CI"
      }
      env {
        name  = "USE_HTTPS"
        value = "true"
      }
      ports {
        container_port = 3903
      }
      resources {
        limits = {
          cpu    = "6000m"
          memory = "24Gi"
        }
      }
    }
    scaling {
      min_instance_count = 1
      max_instance_count = 1
    }
    service_account = google_service_account.orchestration_service_account.email
  }

  depends_on = [
    google_artifact_registry_repository.docker_hub_remote_repository,
    google_service_account.orchestration_service_account,
    google_project_iam_member.orchestration_service_account_cloudsql,
    google_sql_database.orchestration_database
  ]

  lifecycle {
    ignore_changes = [
      template[0].containers[0].resources[0].cpu_idle,
      template[0].containers[1].resources[0].cpu_idle,
      template[0].containers[0].image,
      client,
      client_version,
    ]
  }
}

resource "google_cloud_run_v2_service_iam_member" "orchestration_personnel_access" {
  name     = google_cloud_run_v2_service.orchestration.name
  location = google_cloud_run_v2_service.orchestration.location
  role     = "roles/run.invoker"
  member   = "group:${var.personnel_email}"
}

resource "google_cloud_run_v2_service_iam_member" "orchestration_ui_hub_access" {
  name     = google_cloud_run_v2_service.orchestration.name
  location = google_cloud_run_v2_service.orchestration.location
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.orchestration_service_account.email}"
}

###############################################################
# Cloud Run v2 service for Orchestration UI

resource "google_cloud_run_v2_service" "zipline_ui" {
  name     = "${var.customer_name}-zipline-ui"
  location = var.region

  template {
    vpc_access {
      network_interfaces {
        network    = google_compute_network.zipline_vpc.name
        subnetwork = google_compute_subnetwork.zipline_subnet.name
      }
      egress = "ALL_TRAFFIC"
    }
    service_account = google_service_account.orchestration_service_account.email

    containers {
      name  = "web-ui"
      image = "${google_artifact_registry_repository.docker_hub_remote_repository.location}-docker.pkg.dev/${data.google_project.zipline.project_id}/${google_artifact_registry_repository.docker_hub_remote_repository.repository_id}/ziplineai/web-ui:4d58aeed22d262ed1a7f00532aa3c388eba5cd6c"

      env {
        name  = "API_BASE_URL"
        value = google_cloud_run_v2_service.orchestration.uri
      }
      env {
        name  = "DATABASE_URL"
        value = "postgres://${google_sql_user.orchestration_user.name}@${google_sql_database_instance.orchestration_instance.private_ip_address}:5432/${google_sql_database.orchestration_database.name}"
      }
      env {
        name = "PGPASSWORD"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.db_password.secret_id
            version = "latest"
          }
        }
      }

      resources {
        limits = {
          cpu    = "1000m"
          memory = "1Gi"
        }
      }
      ports {
        container_port = 3000
      }
    }
  }

  depends_on = [
    google_artifact_registry_repository.docker_hub_remote_repository,
    google_service_account.orchestration_service_account,
    google_project_iam_member.orchestration_service_account_secretmanager,
    google_cloud_run_v2_service.orchestration
  ]

  lifecycle {
    ignore_changes = [
      template[0].containers[0].resources[0].cpu_idle,
      template[0].containers[0].image,
      client,
      client_version,
    ]
  }
}

resource "google_cloud_run_v2_service_iam_member" "ui_personnel_access" {
  name     = google_cloud_run_v2_service.zipline_ui.name
  location = google_cloud_run_v2_service.zipline_ui.location
  role     = "roles/run.invoker"
  member   = "group:${var.personnel_email}"
}

resource "google_cloud_run_v2_service_iam_member" "ui_all_access" {
  name     = google_cloud_run_v2_service.zipline_ui.name
  location = google_cloud_run_v2_service.zipline_ui.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}
