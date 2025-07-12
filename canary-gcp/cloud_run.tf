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

resource "google_service_account" "cloud_run_service_account" {
  account_id   = "zipline-cloud-run-sa"
  display_name = "Zipline Cloud Run Service Account"
  project      = data.google_project.zipline.project_id
}

resource "google_project_iam_member" "cloud_run_service_account_role" {
  project = data.google_project.zipline.project_id
  member  = "serviceAccount:${google_service_account.cloud_run_service_account.email}"
  role    = "roles/dataproc.editor"
}

resource "google_project_iam_member" "cloud_run_service_account_storage" {
  project = data.google_project.zipline.project_id
  member  = "serviceAccount:${google_service_account.cloud_run_service_account.email}"
  role    = "roles/storage.objectAdmin"
}

resource "google_project_iam_member" "cloud_run_service_account_cloudsql" {
  project = data.google_project.zipline.project_id
  member  = "serviceAccount:${google_service_account.cloud_run_service_account.email}"
  role    = "roles/cloudsql.client"
}

resource "google_cloud_run_v2_service" "orchestration" {
  name     = "zipline-orchestration"
  location = var.region

  template {

    # Cloud SQL Auth Proxy sidecar container
    containers {
      name  = "cloud-sql-proxy"
      image = "gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.8.0"
      args = [
        "--structured-logs",
        "--port=5432",
        google_sql_database_instance.orchestration-instance.connection_name
      ]

      resources {
        limits = {
          cpu    = "1000m"
          memory = "1Gi"
        }
      }
    }

    containers {
      name  = "orchestration-temporal"
      image = "${google_artifact_registry_repository.docker_hub_remote_repository.location}-docker.pkg.dev/${data.google_project.zipline.project_id}/${google_artifact_registry_repository.docker_hub_remote_repository.repository_id}/ziplineai/orchestration-temporal:v0.0.0"
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
        value = "localhost"
      }
      env {
        name  = "DBNAME"
        value = google_sql_database.orchestration-database.name
      }
      env {
        name  = "SKIP_DEFAULT_NAMESPACE_CREATION"
        value = "false"
      }
      resources {
        limits = {
          cpu    = "4000m" # Increased from 2000m
          memory = "4Gi"   # Increased from 2Gi
        }
      }
    }

    # Main orchestration container
    containers {
      name  = "orchestration-hub"
      image = "${google_artifact_registry_repository.docker_hub_remote_repository.location}-docker.pkg.dev/${data.google_project.zipline.project_id}/${google_artifact_registry_repository.docker_hub_remote_repository.repository_id}/ziplineai/orchestration-hub:v0.0.0"
      env {
        name  = "DB_URL"
        value = "jdbc:postgresql://localhost:5432/${google_sql_database.orchestration-database.name}"
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
          cpu    = "1000m"
          memory = "1Gi"
        }
      }
    }

    service_account = google_service_account.cloud_run_service_account.email
  }

  depends_on = [
    google_artifact_registry_repository.docker_hub_remote_repository,
    google_service_account.cloud_run_service_account,
    google_project_iam_member.cloud_run_service_account_cloudsql
  ]

  lifecycle {
    ignore_changes = [
      template[0].containers[0].resources[0].cpu_idle,
      template[0].containers[1].resources[0].cpu_idle,
      template[0].containers[2].resources[0].cpu_idle,
      template[0].containers[1].image,
      template[0].containers[2].image
    ]
  }
}