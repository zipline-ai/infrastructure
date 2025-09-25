##############################################################
# Service Accounts and IAM Roles

# Service Account for Orchestration
resource "google_service_account" "dev_orchestration_service_account" {
  account_id   = "dev-zipline-orchestration-sa"
  display_name = "Zipline Cloud Run Service Account"
  project      = data.google_project.zipline.project_id
}

resource "google_project_iam_member" "dev_orchestration_service_account_dataproc" {
  project = data.google_project.zipline.project_id
  member  = "serviceAccount:${google_service_account.dev_orchestration_service_account.email}"
  role    = "roles/dataproc.editor"
}

resource "google_project_iam_member" "dev_orchestration_service_account_storage" {
  project = data.google_project.zipline.project_id
  member  = "serviceAccount:${google_service_account.dev_orchestration_service_account.email}"
  role    = "roles/storage.objectAdmin"
}

resource "google_project_iam_member" "dev_orchestration_service_account_cloudsql" {
  project = data.google_project.zipline.project_id
  member  = "serviceAccount:${google_service_account.dev_orchestration_service_account.email}"
  role    = "roles/cloudsql.client"
}

resource "google_project_iam_member" "dev_orchestration_service_account_bigtable" {
  project = data.google_project.zipline.project_id
  member  = "serviceAccount:${google_service_account.dev_orchestration_service_account.email}"
  role    = "roles/bigtable.user"
}

resource "google_project_iam_member" "dev_orchestration_service_account_secretmanager" {
  project = data.google_project.zipline.project_id
  member  = "serviceAccount:${google_service_account.dev_orchestration_service_account.email}"
  role    = "roles/secretmanager.secretAccessor"
}

resource "google_project_iam_member" "dev_orchestration_service_account_monitoring" {
  project = data.google_project.zipline.project_id
  member  = "serviceAccount:${google_service_account.dev_orchestration_service_account.email}"
  role    = "roles/monitoring.metricWriter"
}

resource "google_project_iam_member" "dev_orchestration_service_account_pubsub" {
  project = data.google_project.zipline.project_id
  member  = "serviceAccount:${google_service_account.dev_orchestration_service_account.email}"
  role    = "roles/pubsub.publisher"
}

# Service Account for Temporal Server
resource "google_service_account" "dev_temporal_service_account" {
  account_id   = "dev-zipline-temporal-sa"
  display_name = "Zipline Cloud Run Service Account"
  project      = data.google_project.zipline.project_id
}

resource "google_project_iam_member" "dev_temporal_service_account_secretmanager" {
  project = data.google_project.zipline.project_id
  member  = "serviceAccount:${google_service_account.dev_temporal_service_account.email}"
  role    = "roles/secretmanager.secretAccessor"
}

resource "google_project_iam_member" "dev_temporal_service_account_cloudsql" {
  project = data.google_project.zipline.project_id
  member  = "serviceAccount:${google_service_account.dev_temporal_service_account.email}"
  role    = "roles/cloudsql.client"
}

################################################################
# Cloud Run v2 service for Temporal Server

resource "google_cloud_run_v2_service" "dev_temporal_server" {
  name     = "dev-zipline-temporal-server"
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

    service_account = google_service_account.dev_temporal_service_account.email
    containers {
      image = "${var.region}-docker.pkg.dev/${data.google_project.zipline.project_id}/${module.base_setup.docker_hub_remote_repository_id}/temporalio/auto-setup:1.28.0"
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
        value = google_sql_user.dev_temporal_user.name
      }
      env {
        name = "POSTGRES_PWD"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.dev_db_password.secret_id
            version = "latest"
          }
        }
      }
      env {
        name  = "POSTGRES_SEEDS"
        value = google_sql_database_instance.dev_temporal_instance.private_ip_address
      }
      env {
        name  = "DBNAME"
        value = google_sql_database.dev_temporal_database.name
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
      env {
        name  = "DEFAULT_NAMESPACE_RETENTION"
        value = "168h" # 7 days
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
    google_sql_database_instance.dev_temporal_instance,
    google_service_account.dev_temporal_service_account,
    google_project_iam_member.dev_temporal_service_account_cloudsql,
    google_project_iam_member.dev_temporal_service_account_secretmanager,
  ]
}

resource "google_cloud_run_v2_service_iam_member" "dev_temporal_server_unauthenticated" {
  location = google_cloud_run_v2_service.dev_temporal_server.location
  project  = google_cloud_run_v2_service.dev_temporal_server.project
  name     = google_cloud_run_v2_service.dev_temporal_server.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

################################################################
# Cloud Run v2 service for Temporal UI

resource "google_cloud_run_v2_service" "dev_temporal_ui" {
  name     = "dev-zipline-temporal-ui"
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

    service_account = google_service_account.dev_temporal_service_account.email

    containers {
      image = "${var.region}-docker.pkg.dev/${data.google_project.zipline.project_id}/${module.base_setup.docker_hub_remote_repository_id}/temporalio/ui:2.39.0"
      name  = "temporal-ui"

      ports {
        name           = "http1"
        container_port = 8080
      }

      # Environment variables for PostgreSQL connection
      env {
        name  = "TEMPORAL_ADDRESS"
        value = "${replace(google_cloud_run_v2_service.dev_temporal_server.uri, "https://", "")}:443"
      }
      env {
        name  = "TEMPORAL_TLS_ENABLE_HOST_VERIFICATION"
        value = "false"
      }

      env {
        name  = "TEMPORAL_TLS_SERVER_NAME"
        value = replace(google_cloud_run_v2_service.dev_temporal_server.uri, "https://", "")
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
resource "google_cloud_run_v2_service_iam_member" "dev_temporal_ui_public_access" {
  location = google_cloud_run_v2_service.dev_temporal_ui.location
  project  = google_cloud_run_v2_service.dev_temporal_ui.project
  name     = google_cloud_run_v2_service.dev_temporal_ui.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

################################################################
# Cloud Run v2 Worker Pool for Orchestration Temporal Worker

resource "google_cloud_run_v2_worker_pool" "dev_orchestration_temporal_worker" {
  location     = var.region
  name         = "dev-zipline-orchestration-worker"
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


    service_account = google_service_account.dev_orchestration_service_account.email
    containers {
      image = "${var.region}-docker.pkg.dev/${data.google_project.zipline.project_id}/${module.base_setup.docker_hub_remote_repository_id}/ziplineai/orchestration-temporal-worker:v0.11.2"
      name  = "orchestration-worker"

      env {
        name  = "DB_URL"
        value = "jdbc:postgresql://${google_sql_database_instance.dev_orchestration_instance.private_ip_address}:5432/${google_sql_database.dev_orchestration_database.name}"
      }
      env {
        name  = "DB_USERNAME"
        value = google_sql_user.dev_orchestration_user.name
      }
      env {
        name = "DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.dev_db_password.secret_id
            version = "latest"
          }
        }
      }
      env {
        name  = "TEMPORAL_SERVICE_ADDRESS"
        value = "${replace(google_cloud_run_v2_service.dev_temporal_server.uri, "https://", "")}:443"
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
        value = module.base_setup.bigtable_instance_name
      }
      env {
        name  = "ZIPLINE_LOGS_BUCKET_NAME"
        value = google_storage_bucket.zipline_dev_bucket.name
      }
      env {
        name  = "CUSTOMER_ID"
        value = "dev"
      }
      env {
        name  = "ARTIFACT_PREFIX"
        value = var.artifact_prefix
      }
      env {
        name  = "TABLE_PARTITIONS_DATASET"
        value = google_bigtable_table.dev_table_partitions.name
      }
      env {
        name  = "DATA_QUALITY_METRICS_DATASET"
        value = var.data_quality_metrics_dataset
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

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      template[0].labels,
      client,
      client_version,
    ]
  }
}

################################################################
# Cloud Run v2 service for Orchestration Hub

resource "google_cloud_run_v2_service" "dev_orchestration" {
  name     = "dev-zipline-orchestration"
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
      image = "${var.region}-docker.pkg.dev/${data.google_project.zipline.project_id}/${module.base_setup.docker_hub_remote_repository_id}/ziplineai/orchestration-hub:v0.11.2"
      env {
        name  = "DB_URL"
        value = "jdbc:postgresql://${google_sql_database_instance.dev_orchestration_instance.private_ip_address}:5432/${google_sql_database.dev_orchestration_database.name}"
      }
      env {
        name  = "DB_USERNAME"
        value = google_sql_user.dev_orchestration_user.name
      }
      env {
        name = "DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.dev_db_password.secret_id
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
        value = "dev"
      }
      env {
        name  = "ARTIFACT_PREFIX"
        value = var.artifact_prefix
      }
      env {
        name  = "TEMPORAL_SERVICE_ADDRESS"
        value = "${replace(google_cloud_run_v2_service.dev_temporal_server.uri, "https://", "")}:443"
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
        value = google_bigtable_table.dev_table_partitions.name
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
    service_account = google_service_account.dev_orchestration_service_account.email
  }

  depends_on = [
    google_service_account.dev_orchestration_service_account,
    google_project_iam_member.dev_orchestration_service_account_cloudsql,
    google_sql_database.dev_orchestration_database
  ]

  lifecycle {
    ignore_changes = [
      template[0].containers[0].resources[0].cpu_idle,
      template[0].containers[0].image,
      template[0].labels,
      client,
      client_version,
    ]
  }
}

resource "google_cloud_run_v2_service_iam_member" "dev_orchestration_personnel_access" {
  name     = google_cloud_run_v2_service.dev_orchestration.name
  location = google_cloud_run_v2_service.dev_orchestration.location
  role     = "roles/run.invoker"
  member   = "group:${var.personnel_email}"
}

resource "google_cloud_run_v2_service_iam_member" "dev_orchestration_ui_hub_access" {
  name     = google_cloud_run_v2_service.dev_orchestration.name
  location = google_cloud_run_v2_service.dev_orchestration.location
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.dev_orchestration_service_account.email}"
}

###############################################################
# Cloud Run v2 service for Orchestration UI

resource "google_cloud_run_v2_service" "dev_zipline_ui" {
  name     = "dev-zipline-ui"
  location = var.region

  template {
    vpc_access {
      network_interfaces {
        network    = google_compute_network.zipline_vpc.name
        subnetwork = google_compute_subnetwork.zipline_subnet.name
      }
      egress = "ALL_TRAFFIC"
    }
    service_account = google_service_account.dev_orchestration_service_account.email

    containers {
      name  = "web-ui"
      image = "${var.region}-docker.pkg.dev/${data.google_project.zipline.project_id}/${module.base_setup.docker_hub_remote_repository_id}/ziplineai/web-ui:v0.11.2"

      env {
        name  = "API_BASE_URL"
        value = google_cloud_run_v2_service.dev_orchestration.uri
      }
      env {
        name  = "DATABASE_URL"
        value = "postgres://${google_sql_user.dev_orchestration_user.name}@${google_sql_database_instance.dev_orchestration_instance.private_ip_address}:5432/${google_sql_database.dev_orchestration_database.name}"
      }
      env {
        name = "PGPASSWORD"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.dev_db_password.secret_id
            version = "latest"
          }
        }
      }
      env {
        name  = "GOOGLE_CLOUD_PROJECT"
        value = data.google_project.zipline.project_id
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
    google_service_account.dev_orchestration_service_account,
    google_project_iam_member.dev_orchestration_service_account_secretmanager,
    google_cloud_run_v2_service.dev_orchestration
  ]

  lifecycle {
    ignore_changes = [
      template[0].containers[0].resources[0].cpu_idle,
      template[0].containers[0].image,
      template[0].labels,
      client,
      client_version,
    ]
  }
}

resource "google_cloud_run_v2_service_iam_member" "dev_ui_all_access" {
  name     = google_cloud_run_v2_service.dev_zipline_ui.name
  location = google_cloud_run_v2_service.dev_zipline_ui.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

################################################################
# Cloud Run v2 service for Chronon Fetcher

resource "google_cloud_run_v2_service" "dev_chronon_fetcher" {
  name     = "dev-zipline-chronon-fetcher"
  location = var.region
  project  = data.google_project.zipline.project_id

  template {
    annotations = {
      "run.googleapis.com/container-dependencies" = jsonencode({
        collector = ["chronon-fetcher"]
      })
    }

    vpc_access {
      network_interfaces {
        network    = google_compute_network.zipline_vpc.name
        subnetwork = google_compute_subnetwork.zipline_subnet.name
      }
      egress = "ALL_TRAFFIC"
    }

    service_account = google_service_account.dev_orchestration_service_account.email

    containers {
      image = "${var.region}-docker.pkg.dev/${data.google_project.zipline.project_id}/${module.base_setup.docker_hub_remote_repository_id}/ziplineai/chronon-fetcher:latest"
      name  = "chronon-fetcher"

      ports {
        name           = "http1"
        container_port = 9000
      }

      env {
        name  = "GCP_PROJECT_ID"
        value = data.google_project.zipline.project_id
      }
      env {
        name  = "GOOGLE_CLOUD_PROJECT"
        value = data.google_project.zipline.project_id
      }
      env {
        name  = "GCP_BIGTABLE_INSTANCE_ID"
        value = module.base_setup.bigtable_instance_name
      }
      env {
        name  = "CHRONON_METRICS_READER"
        value = "http"
      }
      env {
        name  = "EXPORTER_OTLP_ENDPOINT"
        value = "http://localhost:4318"
      }
      env {
        name  = "FETCHER_OOC_TOPIC_INFO"
        value = "pubsub://${google_pubsub_topic.canary_logging_ooc.name}"
      }

      resources {
        limits = {
          cpu    = "2"
          memory = "4Gi"
        }
      }

      startup_probe {
        http_get {
          path = "/ping"
          port = 9000
        }
        initial_delay_seconds = 20
        period_seconds        = 10
        timeout_seconds       = 5
        failure_threshold     = 10
      }
    }

    # OTEL Collector sidecar for metrics export
    containers {
      image = "otel/opentelemetry-collector-contrib:0.91.0"
      name  = "collector"

      args = ["--config=env:OTEL_CONFIG_YAML"]

      env {
        name  = "OTEL_CONFIG_YAML"
        value = yamlencode({
          receivers = {
            otlp = {
              protocols = {
                grpc = {
                  endpoint = "0.0.0.0:4317"
                }
                http = {
                  endpoint = "0.0.0.0:4318"
                }
              }
            }
          }
          processors = {
            resourcedetection = {
              detectors = ["env", "gcp"]
              timeout = "5s"
              override = false
            }
            resource = {
              attributes = [
                {
                  key = "location"
                  value = var.region
                  action = "upsert"
                },
                {
                  key = "namespace"
                  value = var.name
                  action = "upsert"
                },
                {
                  key = "cluster"
                  value = "zipline-${var.name}"
                  action = "upsert"
                }
              ]
            }
          }
          exporters = {
            googlemanagedprometheus = {
              project = data.google_project.zipline.project_id
            }
          }
          service = {
            pipelines = {
              metrics = {
                receivers = ["otlp"]
                processors = ["resourcedetection", "resource"]
                exporters = ["googlemanagedprometheus"]
              }
            }
          }
        })
      }

      resources {
        limits = {
          cpu    = "500m"
          memory = "512Mi"
        }
      }

    }

    scaling {
      min_instance_count = 1
      max_instance_count = 5
    }
  }

  depends_on = [
    google_service_account.dev_orchestration_service_account,
  ]
}

# IAM policy to allow orchestration service account to invoke chronon services
resource "google_cloud_run_v2_service_iam_member" "dev_chronon_fetcher_access" {
  location = google_cloud_run_v2_service.dev_chronon_fetcher.location
  project  = google_cloud_run_v2_service.dev_chronon_fetcher.project
  name     = google_cloud_run_v2_service.dev_chronon_fetcher.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.dev_orchestration_service_account.email}"
}

# IAM policy to allow all users to invoke chronon services (public access)
resource "google_cloud_run_v2_service_iam_member" "dev_chronon_fetcher_all_access" {
  location = google_cloud_run_v2_service.dev_chronon_fetcher.location
  project  = google_cloud_run_v2_service.dev_chronon_fetcher.project
  name     = google_cloud_run_v2_service.dev_chronon_fetcher.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

