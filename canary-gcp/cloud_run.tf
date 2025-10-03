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

resource "google_project_iam_member" "dev_orchestration_logging" {
  project = data.google_project.zipline.project_id
  role    = "roles/logging.viewer"
  member  = "serviceAccount:${google_service_account.dev_orchestration_service_account.email}"
}


resource "google_project_iam_member" "dev_orchestration_logging_writer" {
  project = data.google_project.zipline.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.dev_orchestration_service_account.email}"
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
        name  = "USE_TEMPORAL"
        value = false
      }
      env {
        name  = "VERTICLE_CLASS"
        value = "ai.chronon.hub.GCPOrchestrationVerticle,ai.chronon.hub.GCPWorkflowExecutionVerticle"
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
        name  = "ORCHESTRATION_PORT"
        value = 3903
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
        name  = "USE_HTTPS"
        value = "true"
      }
      env {
        name  = "EXPORTER_OTLP_ENDPOINT"
        value = "http://localhost:4318"
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
    # OpenTelemetry sidecar container
    containers {
      image = "otel/opentelemetry-collector-contrib:0.91.0"
      name  = "otel-collector"

      args = ["--config=env:OTEL_CONFIG_YAML"]

      env {
        name = "OTEL_CONFIG_YAML"
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
              timeout   = "5s"
              override  = false
            }
            resource = {
              attributes = [
                {
                  key    = "location"
                  value  = var.region
                  action = "upsert"
                },
                {
                  key    = "namespace"
                  value  = "dev"
                  action = "upsert"
                },
                {
                  key    = "cluster"
                  value  = "zipline-dev"
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
                receivers  = ["otlp"]
                processors = ["resourcedetection", "resource"]
                exporters  = ["googlemanagedprometheus"]
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
      env {
        name  = "PUBLIC_ORCHESTRATION_VERSION"
        value = "2"
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
        name = "OTEL_CONFIG_YAML"
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
              timeout   = "5s"
              override  = false
            }
            resource = {
              attributes = [
                {
                  key    = "location"
                  value  = var.region
                  action = "upsert"
                },
                {
                  key    = "namespace"
                  value  = "dev"
                  action = "upsert"
                },
                {
                  key    = "cluster"
                  value  = "zipline-dev"
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
                receivers  = ["otlp"]
                processors = ["resourcedetection", "resource"]
                exporters  = ["googlemanagedprometheus"]
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

