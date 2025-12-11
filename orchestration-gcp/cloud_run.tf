# Google Artifact Registry - Remote Repository for Docker Hub
resource "google_artifact_registry_repository" "docker_hub_remote_repository" {
  format        = "DOCKER"
  repository_id = "${var.name_prefix}-zipline-docker-hub-proxy"
  location      = var.region
  description   = "Remote repository for Docker images from Docker Hub"
  mode          = "REMOTE_REPOSITORY"
  remote_repository_config {
    description = "Proxy repository for ziplineai images on Docker Hub"
    docker_repository {
      public_repository = "DOCKER_HUB"
    }

    upstream_credentials {
      username_password_credentials {
        username                = "ziplineai"
        password_secret_version = google_secret_manager_secret_version.docker_token_version.name
      }
    }
  }
  depends_on = [
    google_secret_manager_secret_iam_member.artifact_registry_secret_access
  ]
}

resource "google_secret_manager_secret" "docker_token" {
  secret_id = "${var.name_prefix}-zipline-docker-token"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "docker_token_version" {
  secret      = google_secret_manager_secret.docker_token.id
  secret_data = var.docker_hub_token
}

resource "google_secret_manager_secret_iam_member" "artifact_registry_secret_access" {
  secret_id = google_secret_manager_secret.docker_token.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:service-${var.project_number}@gcp-sa-artifactregistry.iam.gserviceaccount.com"
}

data "google_project" "zipline" {}

# Enable required APIs
resource "google_project_service" "cloudrun_api" {
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
  account_id   = "${var.name_prefix}-zipline-orch-sa"
  display_name = "Zipline Cloud Run Service Account"
  project      = data.google_project.zipline.project_id
}

##############################################################
# Service Account for Eval (Metadata-only access)

resource "google_service_account" "eval_service_account" {
  account_id   = "${var.name_prefix}-zipline-eval-sa"
  display_name = "Chronon Eval Metadata Reader"
  description  = "Service account for Chronon eval with metadata-only access (no data access)"
  project      = data.google_project.zipline.project_id
}

# Grant BigQuery metadata viewer role (read table schemas, partitions)
resource "google_project_iam_member" "eval_metadata_viewer" {
  project = data.google_project.zipline.project_id
  role    = "roles/bigquery.metadataViewer"
  member  = "serviceAccount:${google_service_account.eval_service_account.email}"
}

# Grant BigQuery job user role (run metadata queries)
resource "google_project_iam_member" "eval_job_user" {
  project = data.google_project.zipline.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.eval_service_account.email}"
}

# Grant Cloud SQL client access for eval database connection
resource "google_project_iam_member" "eval_cloudsql" {
  project = data.google_project.zipline.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.eval_service_account.email}"
}

# Grant logging permissions
resource "google_project_iam_member" "eval_logging_writer" {
  project = data.google_project.zipline.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.eval_service_account.email}"
}

# Grant monitoring permissions
resource "google_project_iam_member" "eval_monitoring" {
  project = data.google_project.zipline.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.eval_service_account.email}"
}

# Grant secret manager access for database credentials
resource "google_project_iam_member" "eval_secretmanager" {
  project = data.google_project.zipline.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.eval_service_account.email}"
}

# Grant service account token creator to specified users/groups for impersonation
resource "google_service_account_iam_member" "eval_impersonation" {
  for_each = toset(var.eval_impersonation_users)

  service_account_id = google_service_account.eval_service_account.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = each.value
}

##############################################################
# Orchestration Service Account IAM Roles

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

resource "google_project_iam_member" "orchestration_logging" {
  project = data.google_project.zipline.project_id
  role    = "roles/logging.viewer"
  member  = "serviceAccount:${google_service_account.orchestration_service_account.email}"
}


resource "google_project_iam_member" "orchestration_logging_writer" {
  project = data.google_project.zipline.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.orchestration_service_account.email}"
}

resource "google_project_iam_member" "orchestration_monitoring" {
  project = data.google_project.zipline.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.orchestration_service_account.email}"
}

# Grant Dataproc access to the Orchestration service account
resource "google_service_account_iam_member" "orchestration_impersonation_dataproc" {
  service_account_id = var.dataproc_service_account
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.orchestration_service_account.email}"
}

################################################################
# Cloud Run v2 service for Orchestration Hub

resource "google_cloud_run_v2_service" "orchestration" {
  name     = "${var.name_prefix}-zipline-orchestration"
  location = var.region

  custom_audiences = [
    var.hub_domain != "" ? "https://${var.hub_domain}" : "https://${var.name_prefix}-zipline-orchestration-${data.google_project.zipline.number}.${var.region}.run.app"
  ]

  template {
    annotations = {
      "run.googleapis.com/container-dependencies" = jsonencode({
        otel-collector = ["orchestration-hub"]
      })
    }

    vpc_access {
      network_interfaces {
        network    = var.vpc_name
        subnetwork = var.subnet_name
      }
      egress = "ALL_TRAFFIC"
    }
    # Main orchestration container
    containers {
      name  = "orchestration-hub"
      image = "${google_artifact_registry_repository.docker_hub_remote_repository.location}-docker.pkg.dev/${data.google_project.zipline.project_id}/${google_artifact_registry_repository.docker_hub_remote_repository.repository_id}/ziplineai/orchestration-hub:${var.zipline_version}"
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
        value = var.bigtable_instance_name
      }
      env {
        name  = "CUSTOMER_ID"
        value = var.name_prefix
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
        value = var.table_partitions_dataset
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
        name  = "CHRONON_METRICS_READER"
        value = "http"
      }
      env {
        name  = "EXPORTER_OTLP_ENDPOINT"
        value = "http://localhost:4318"
      }
      env {
        name  = "HUB_FRONTEND_URL"
        value = var.zipline_ui_domain != "" ? "https://${var.zipline_ui_domain}" : "https://${var.name_prefix}-zipline-ui-${data.google_project.zipline.number}.${var.region}.run.app"
      }
      ports {
        container_port = 3903
      }
      resources {
        limits = {
          cpu    = "6000m"
          memory = "16Gi"
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
                  value  = var.name_prefix
                  action = "upsert"
                },
                {
                  key    = "cluster"
                  value  = "zipline-${var.name_prefix}"
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
      template[0].containers[0].image,
      template[0].labels,
      client,
      client_version,
      scaling,
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
  provider     = google-beta
  name         = "${var.name_prefix}-zipline-ui"
  location     = var.region
  launch_stage = "BETA"
  iap_enabled  = true

  custom_audiences = [
    var.zipline_ui_domain != "" ? "https://${var.zipline_ui_domain}" : "https://${var.name_prefix}-zipline-ui-${data.google_project.zipline.number}.${var.region}.run.app"
  ]
  template {
    vpc_access {
      network_interfaces {
        network    = var.vpc_name
        subnetwork = var.subnet_name
      }
      egress = "ALL_TRAFFIC"
    }
    service_account = google_service_account.orchestration_service_account.email

    containers {
      name  = "web-ui"
      image = "${google_artifact_registry_repository.docker_hub_remote_repository.location}-docker.pkg.dev/${data.google_project.zipline.project_id}/${google_artifact_registry_repository.docker_hub_remote_repository.repository_id}/ziplineai/web-ui:${var.zipline_version}"

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
      env {
        name  = "GOOGLE_CLOUD_PROJECT"
        value = data.google_project.zipline.project_id
      }
      env {
        name  = "PUBLIC_ORCH_SERVER_NAME"
        value = "canary-zipline-orchestration"
      }
      env {
        name = "FETCHER_BASE_URL"
        value = google_cloud_run_v2_service.chronon_fetcher.uri
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
      template[0].labels,
      client,
      client_version,
      scaling,
    ]
  }
}

resource "google_cloud_run_v2_service_iam_member" "ui_personnel_access" {
  name     = google_cloud_run_v2_service.zipline_ui.name
  location = google_cloud_run_v2_service.zipline_ui.location
  role     = "roles/run.invoker"
  member   = "group:${var.personnel_email}"
}

resource "google_cloud_run_v2_service_iam_member" "ui_iap_access" {
  name     = google_cloud_run_v2_service.zipline_ui.name
  location = google_cloud_run_v2_service.zipline_ui.location
  role     = "roles/run.invoker"
  member   = "serviceAccount:service-${data.google_project.zipline.number}@gcp-sa-iap.iam.gserviceaccount.com"
}

resource "google_iap_web_iam_member" "ui_iap_user_access" {
  project = data.google_project.zipline.project_id
  role    = "roles/iap.httpsResourceAccessor"
  member  = "group:${var.personnel_email}"

  depends_on = [
    google_cloud_run_v2_service.zipline_ui,
    google_cloud_run_v2_service_iam_member.ui_iap_access
  ]
}


output "docker_hub_remote_repository_id" {
  value = google_artifact_registry_repository.docker_hub_remote_repository.repository_id
}

output "orchestration_service_name" {
  value = google_cloud_run_v2_service.orchestration.name
}

output "orchestration_service_account_id" {
  value = google_service_account.orchestration_service_account.id
}

################################################################
# Cloud Run v2 service for Chronon Fetcher

resource "google_cloud_run_v2_service" "chronon_fetcher" {
  name     = "${var.name_prefix}-zipline-chronon-fetcher"
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
        network    = var.vpc_name
        subnetwork = var.subnet_name
      }
      egress = "ALL_TRAFFIC"
    }

    service_account = google_service_account.orchestration_service_account.email

    containers {
      image = "${var.region}-docker.pkg.dev/${data.google_project.zipline.project_id}/${google_artifact_registry_repository.docker_hub_remote_repository.repository_id}/ziplineai/chronon-fetcher:latest"
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
        value = var.bigtable_instance_name
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
        value = "pubsub://${google_pubsub_topic.logging_ooc.name}"
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
                  value  = var.name_prefix
                  action = "upsert"
                },
                {
                  key    = "cluster"
                  value  = "zipline-${var.name_prefix}"
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
    google_service_account.orchestration_service_account,
  ]
}

# IAM policy to allow orchestration service account to invoke chronon services
resource "google_cloud_run_v2_service_iam_member" "chronon_fetcher_access" {
  location = google_cloud_run_v2_service.chronon_fetcher.location
  project  = google_cloud_run_v2_service.chronon_fetcher.project
  name     = google_cloud_run_v2_service.chronon_fetcher.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.orchestration_service_account.email}"
}

# IAM policy to allow all users to invoke chronon services (public access)
resource "google_cloud_run_v2_service_iam_member" "chronon_fetcher_all_access" {
  location = google_cloud_run_v2_service.chronon_fetcher.location
  project  = google_cloud_run_v2_service.chronon_fetcher.project
  name     = google_cloud_run_v2_service.chronon_fetcher.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

################################################################
# Cloud Run v2 service for Chronon Eval

resource "google_cloud_run_v2_service" "chronon_eval" {
  name                = "${var.name_prefix}-zipline-chronon-eval"
  location            = var.region
  project             = data.google_project.zipline.project_id
  deletion_protection = false

  template {
    vpc_access {
      network_interfaces {
        network    = var.vpc_name
        subnetwork = var.subnet_name
      }
      egress = "ALL_TRAFFIC"
    }

    service_account = google_service_account.eval_service_account.email

    containers {
      image = "${google_artifact_registry_repository.docker_hub_remote_repository.location}-docker.pkg.dev/${data.google_project.zipline.project_id}/${google_artifact_registry_repository.docker_hub_remote_repository.repository_id}/ziplineai/chronon-eval:${var.zipline_version}"
      name  = "chronon-eval"

      ports {
        name           = "http1"
        container_port = 3904
      }

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
        value = var.bigtable_instance_name
      }
      env {
        name  = "EVAL_SERVICE_ACCOUNT_EMAIL"
        value = google_service_account.eval_service_account.email
      }

      resources {
        limits = {
          cpu    = "4"
          memory = "8Gi"
        }
      }

      startup_probe {
        http_get {
          path = "/ping"
          port = 3904
        }
        initial_delay_seconds = 30
        period_seconds        = 10
        timeout_seconds       = 5
        failure_threshold     = 10
      }
    }

    scaling {
      min_instance_count = 0
      max_instance_count = 3
    }
  }

  depends_on = [
    google_service_account.eval_service_account,
    google_sql_database.orchestration_database
  ]
  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
    ]
  }
}

# IAM policy to allow orchestration service account to invoke eval service
resource "google_cloud_run_v2_service_iam_member" "eval_orchestration_access" {
  location = google_cloud_run_v2_service.chronon_eval.location
  project  = google_cloud_run_v2_service.chronon_eval.project
  name     = google_cloud_run_v2_service.chronon_eval.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.orchestration_service_account.email}"
}

# IAM policy to allow personnel group to invoke eval service
resource "google_cloud_run_v2_service_iam_member" "eval_personnel_access" {
  location = google_cloud_run_v2_service.chronon_eval.location
  project  = google_cloud_run_v2_service.chronon_eval.project
  name     = google_cloud_run_v2_service.chronon_eval.name
  role     = "roles/run.invoker"
  member   = "group:${var.personnel_email}"
}

################################################################
# Domain Mapping for Cloud Run services

resource "google_cloud_run_domain_mapping" "ui_domain_mapping" {
  count    = var.zipline_ui_domain != "" ? 1 : 0
  name     = var.zipline_ui_domain
  location = var.region
  spec {
    route_name = google_cloud_run_v2_service.zipline_ui.name
  }
  metadata {
    namespace = data.google_project.zipline.project_id
  }

  depends_on = [
    google_cloud_run_v2_service.zipline_ui
  ]
}

resource "google_cloud_run_domain_mapping" "orchestration_domain_mapping" {
  count    = var.hub_domain != "" ? 1 : 0
  name     = var.hub_domain
  location = var.region
  spec {
    route_name = google_cloud_run_v2_service.orchestration.name
  }
  metadata {
    namespace = data.google_project.zipline.project_id
  }

  depends_on = [
    google_cloud_run_v2_service.orchestration
  ]
}

output "UI_DNS_Instructions" {
  value = var.zipline_ui_domain != "" ? "Create a CNAME record pointing ${var.zipline_ui_domain} to ghs.googlehosted.com. For more details, see https://cloud.google.com/run/docs/mapping-custom-domains#dns_update" : null
}

output "Hub_DNS_Instructions" {
  value = var.hub_domain != "" ? "Create a CNAME record pointing ${var.hub_domain} to ghs.googlehosted.com. For more details, see https://cloud.google.com/run/docs/mapping-custom-domains#dns_update" : null
}

output "eval_service_url" {
  value       = google_cloud_run_v2_service.chronon_eval.uri
  description = "URL of the Chronon Eval service"
}

output "eval_service_account_email" {
  value       = google_service_account.eval_service_account.email
  description = "Email of the Chronon Eval metadata service account"
}