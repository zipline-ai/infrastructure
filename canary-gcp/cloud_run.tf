resource "google_artifact_registry_repository" "docker_hub_remote_repository" {
  format        = "DOCKER"
  repository_id = "zipline-docker-hub-proxy"
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


# Service Accounts for Cloud Run Services
resource "google_service_account" "orchestration_cloud_run_service_account" {
  account_id   = "zipline-cloud-run-sa"
  display_name = "Zipline Cloud Run Service Account"
  project      = data.google_project.zipline.project_id
}

resource "google_project_iam_member" "cloud_run_service_account_role" {
  project = data.google_project.zipline.project_id
  member  = "serviceAccount:${google_service_account.orchestration_cloud_run_service_account.email}"
  role    = "roles/dataproc.editor"
}

resource "google_project_iam_member" "cloud_run_service_account_storage" {
  project = data.google_project.zipline.project_id
  member  = "serviceAccount:${google_service_account.orchestration_cloud_run_service_account.email}"
  role    = "roles/storage.objectAdmin"
}

resource "google_project_iam_member" "cloud_run_service_account_cloudsql" {
  project = data.google_project.zipline.project_id
  member  = "serviceAccount:${google_service_account.orchestration_cloud_run_service_account.email}"
  role    = "roles/cloudsql.client"
}

resource "google_project_iam_member" "cloud_run_service_account_bigtable" {
  project = data.google_project.zipline.project_id
  member  = "serviceAccount:${google_service_account.orchestration_cloud_run_service_account.email}"
  role    = "roles/bigtable.user"
}

resource "google_service_account" "temporal_cloud_run_service_account" {
  account_id   = "zipline-temporal-cloud-run-sa"
  display_name = "Zipline Temporal Cloud Run Service Account"
  project      = data.google_project.zipline.project_id
}

resource "google_service_account" "ui_cloud_run_service_account" {
  account_id   = "zipline-ui-cloud-run-sa"
  display_name = "Zipline UI Cloud Run Service Account"
  project      = data.google_project.zipline.project_id
}


# Cloud Run Services
resource "google_cloud_run_v2_service" "orchestration" {
  name     = "zipline-orchestration"
  location = var.region

  template {
    # Main orchestration container
    containers {
      name  = "orchestration-hub"
      image = "${google_artifact_registry_repository.docker_hub_remote_repository.location}-docker.pkg.dev/${data.google_project.zipline.project_id}/${google_artifact_registry_repository.docker_hub_remote_repository.repository_id}/ziplineai/orchestration-hub:v0.0.0"
      env {
        name  = "DB_URL"
        value = "jdbc:postgresql://${google_sql_database_instance.orchestration-instance.ip_address[0].ip_address}:5432/${google_sql_database.orchestration-database.name}"
      }
      env {
        name  = "DB_USERNAME"
        value = google_sql_user.locker.name
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
        value = "localhost:7233"
      }
      env {
        name  = "TEMPORAL_NAMESPACE"
        value = "default"
      }
      env {
        name  = "ORCHESTRATION_PORT"
        value = 3903
      }
      ports {
        container_port = 3903
      }
      resources {
        limits = {
          cpu    = "2"
          memory = "8Gi"
        }
      }
    }
    scaling {
      min_instance_count = 1
      max_instance_count = 1
    }

    # Temporal auto-setup container
    containers {
      name  = "zipline-temporal"
      image = "${google_artifact_registry_repository.docker_hub_remote_repository.location}-docker.pkg.dev/${data.google_project.zipline.project_id}/${google_artifact_registry_repository.docker_hub_remote_repository.repository_id}/temporalio/auto-setup:1.28.0"

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
        value = google_sql_user.locker.name
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
        value = google_sql_database_instance.orchestration-instance.ip_address[0].ip_address
      }
      env {
        name  = "DBNAME"
        value = google_sql_database.orchestration-database.name
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

      resources {
        limits = {
          cpu    = "2000m"
          memory = "2Gi"
        }
      }
    }

    service_account = google_service_account.orchestration_cloud_run_service_account.email
  }
  depends_on = [
    google_artifact_registry_repository.docker_hub_remote_repository,
    google_service_account.orchestration_cloud_run_service_account,
    google_project_iam_member.cloud_run_service_account_cloudsql,
    google_sql_database.orchestration-database
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

resource "google_cloud_run_v2_service" "zipline_ui" {
  name     = "zipline-ui"
  location = var.region

  template {
    containers {
      name  = "web-ui"
      image = "${google_artifact_registry_repository.docker_hub_remote_repository.location}-docker.pkg.dev/${data.google_project.zipline.project_id}/${google_artifact_registry_repository.docker_hub_remote_repository.repository_id}/ziplineai/web-ui:v0.0.0"

      env {
        name  = "API_BASE_URL"
        value = google_cloud_run_v2_service.orchestration.uri
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

    service_account = google_service_account.ui_cloud_run_service_account.email
  }

  depends_on = [
    google_artifact_registry_repository.docker_hub_remote_repository,
    google_service_account.ui_cloud_run_service_account
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


# IAM bindings for service-to-service communication
resource "google_cloud_run_service_iam_member" "ui_to_orchestration" {
  service  = google_cloud_run_v2_service.orchestration.name
  location = var.region
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.ui_cloud_run_service_account.email}"

  depends_on = [
    google_cloud_run_v2_service.orchestration
  ]
}

# Allow unauthenticated requests to the Web UI
resource "google_cloud_run_service_iam_binding" "ui_allow_access" {
  service = google_cloud_run_v2_service.zipline_ui.name
  role    = "roles/run.invoker"
  members = [
    "allUsers"
  ]
}

# Cloud Run Services
resource "google_cloud_run_v2_service" "orchestration_v2" {
  name     = "zipline-orchestration-v2"
  location = var.region

  template {
    # Main orchestration container
    containers {
      name  = "orchestration-hub-v2"
      image = "${google_artifact_registry_repository.docker_hub_remote_repository.location}-docker.pkg.dev/${data.google_project.zipline.project_id}/${google_artifact_registry_repository.docker_hub_remote_repository.repository_id}/ziplineai/orchestration-hub:v0.0.0"
      env {
        name  = "DB_URL"
        value = "jdbc:postgresql://${google_sql_database_instance.orchestration-instance.ip_address[0].ip_address}:5432/${google_sql_database.orchestration-database.name}"
      }
      env {
        name  = "DB_USERNAME"
        value = google_sql_user.locker.name
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
        value = "${kubernetes_service.temporal_service.status[0].load_balancer[0].ingress[0].ip}:7233"
      }
      env {
        name  = "TEMPORAL_NAMESPACE"
        value = "default"
      }
      env {
        name  = "ORCHESTRATION_PORT"
        value = 3903
      }
      ports {
        container_port = 3903
      }
      resources {
        limits = {
          cpu    = "2"
          memory = "8Gi"
        }
      }
    }
    scaling {
      min_instance_count = 1
      max_instance_count = 1
    }

    service_account = google_service_account.orchestration_cloud_run_service_account.email
  }
  depends_on = [
    google_artifact_registry_repository.docker_hub_remote_repository,
    google_service_account.orchestration_cloud_run_service_account,
    google_project_iam_member.cloud_run_service_account_cloudsql,
    google_sql_database.orchestration-database
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

resource "google_cloud_run_v2_service" "zipline_ui_v2" {
  name     = "zipline-ui-v2"
  location = var.region

  template {
    containers {
      name  = "web-ui-v2"
      image = "${google_artifact_registry_repository.docker_hub_remote_repository.location}-docker.pkg.dev/${data.google_project.zipline.project_id}/${google_artifact_registry_repository.docker_hub_remote_repository.repository_id}/ziplineai/web-ui:v0.0.0"

      env {
        name  = "API_BASE_URL"
        value = google_cloud_run_v2_service.orchestration_v2.uri
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

    service_account = google_service_account.ui_cloud_run_service_account.email
  }

  depends_on = [
    google_artifact_registry_repository.docker_hub_remote_repository,
    google_service_account.ui_cloud_run_service_account,
    google_cloud_run_service_iam_member.ui_to_orchestration_v2
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

# IAM bindings for service-to-service communication
resource "google_cloud_run_service_iam_member" "ui_to_orchestration_v2" {
  service  = google_cloud_run_v2_service.orchestration_v2.name
  location = var.region
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.ui_cloud_run_service_account.email}"

  depends_on = [
    google_cloud_run_v2_service.orchestration_v2
  ]
}

# Allow unauthenticated requests to the Web UI
resource "google_cloud_run_service_iam_binding" "ui_v2_allow_access" {
  service = google_cloud_run_v2_service.zipline_ui_v2.name
  role    = "roles/run.invoker"
  members = [
    "allUsers"
  ]
}