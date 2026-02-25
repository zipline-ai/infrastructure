resource "google_service_account" "dataproc_sa" {
  account_id   = "dataproc"
  display_name = "Dataproc SA"
  lifecycle {
    prevent_destroy = true
  }
}

# Dataproc Roles

resource "google_project_iam_member" "dataproc_worker" {
  project = data.google_project.zipline.project_id
  role    = "roles/dataproc.worker"
  member  = "serviceAccount:${google_service_account.dataproc_sa.email}"
}

# BigQuery Roles

resource "google_project_iam_member" "dataproc_bigquery" {
  project = data.google_project.zipline.project_id
  role    = "roles/bigquery.user"
  member  = "serviceAccount:${google_service_account.dataproc_sa.email}"
}

resource "google_project_iam_member" "dataproc_bigquery_connection" {
  project = data.google_project.zipline.project_id
  role    = "roles/bigquery.connectionUser"
  member  = "serviceAccount:${google_service_account.dataproc_sa.email}"
}

resource "google_project_iam_member" "dataproc_bigquery_data_editor" {
  project = data.google_project.zipline.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.dataproc_sa.email}"
}

# Bigtable Roles

resource "google_project_iam_member" "dataproc_bigtable_user" {
  project = data.google_project.zipline.project_id
  role    = "roles/bigtable.user"
  member  = "serviceAccount:${google_service_account.dataproc_sa.email}"
}

# Storage Roles

resource "google_storage_bucket_iam_member" "dataproc-bucket-binding" {
  bucket = google_storage_bucket.zipline.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.dataproc_sa.email}"
}

resource "google_storage_bucket_iam_member" "dataproc-bucket-viewer-binding" {
  bucket = trimprefix(var.artifact_prefix, "gs://")
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.dataproc_sa.email}"
}

# PubSub Roles

resource "google_project_iam_member" "dataproc_pubsub_editor" {
  project = data.google_project.zipline.project_id
  role    = "roles/pubsub.editor"
  member  = "serviceAccount:${google_service_account.dataproc_sa.email}"
}

# Cloud Profiler Roles

resource "google_project_iam_member" "dataproc_cloud_profiler_agent" {
  project = data.google_project.zipline.project_id
  role    = "roles/cloudprofiler.agent"
  member  = "serviceAccount:${google_service_account.dataproc_sa.email}"
}

# Autoscaling Policy

resource "google_dataproc_autoscaling_policy" "zipline_autoscaling_policy" {
  project   = data.google_project.zipline.project_id
  location  = var.region
  policy_id = "zipline-${lower(var.customer_name)}-autoscaling-policy"

  worker_config {
    min_instances = 2
    max_instances = 256
  }

  basic_algorithm {
    cooldown_period = "120s"
    yarn_config {
      graceful_decommission_timeout = "120s"
      scale_down_factor             = 0.5
      scale_up_factor               = 1.0
    }
  }
}

# Grant access to the service account to allow personnel users to create a dataproc cluster
resource "google_service_account_iam_member" "personnel_dataproc_access" {
  service_account_id = google_service_account.dataproc_sa.id
  role               = "roles/iam.serviceAccountUser"
  member             = "group:${var.personnel_email}"

  depends_on = [
    google_service_account.dataproc_sa
  ]
}

# Dataproc Cluster

resource "google_dataproc_cluster" "zipline_dataproc" {
  name   = "zipline-${lower(var.customer_name)}-cluster"
  region = var.region

  cluster_config {
    master_config {
      num_instances = 1
      machine_type  = "n2-highmem-16"
      disk_config {
        boot_disk_type    = "pd-standard"
        boot_disk_size_gb = 1024
      }
    }
    worker_config {
      machine_type = "n1-highmem-16"
      disk_config {
        boot_disk_type    = "pd-standard"
        boot_disk_size_gb = 64
        num_local_ssds    = 2
      }
    }

    initialization_action {
      script = "${var.artifact_prefix}/scripts/copy_java_security.sh"
    }

    # Add initialization action to install ops agent for Flink metrics
    initialization_action {
      script = "${var.artifact_prefix}/scripts/opsagent_setup.sh"
    }

    dynamic "initialization_action" {
      for_each = var.dataproc_init_actions
      content {
        script = initialization_action.value
      }
    }

    gce_cluster_config {
      service_account = google_service_account.dataproc_sa.email
      service_account_scopes = [
        "cloud-platform",
        "monitoring",
        "https://www.googleapis.com/auth/cloud.useraccounts.readonly",
        "https://www.googleapis.com/auth/devstorage.read_write",
        "https://www.googleapis.com/auth/logging.write",
      ]
      subnetwork = var.dataproc_subnetwork
      tags       = concat(var.dataproc_tags, ["dataproc-node"])
      metadata = {
        hive-version           = "3.1.2",
        SPARK_BQ_CONNECTOR_URL = "gs://spark-lib/bigquery/spark-3.5-bigquery-0.42.1.jar",
        artifact_prefix        = var.artifact_prefix,
      }
      internal_ip_only = true
    }
    software_config {
      image_version = "2.2.66-debian12"
      optional_components = [
        "FLINK",
        "JUPYTER",
      ]
      override_properties = {
        "flink:env.java.opts.client"                                      = "-Djava.net.preferIPv4Stack=true -Djava.security.properties=/etc/flink/conf/java.security"
        "dataproc:dataproc.logging.stackdriver.enable"                    = "true"
        "dataproc:jobs.file-backed-output.enable"                         = "true"
        "dataproc:dataproc.logging.stackdriver.job.driver.enable"         = "true"
        "dataproc:dataproc.logging.stackdriver.job.yarn.container.enable" = "true"
      }
    }
    endpoint_config {
      enable_http_port_access = true
    }
    autoscaling_config {
      policy_uri = google_dataproc_autoscaling_policy.zipline_autoscaling_policy.name
    }
  }
  depends_on = [
    google_project_iam_member.dataproc_worker
  ]

}

output "dataproc_service_account_id" {
  value = google_service_account.dataproc_sa.id
}