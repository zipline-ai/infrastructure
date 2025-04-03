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

resource "google_project_iam_member" "dataproc_bigquery_admin" {
  project = data.google_project.zipline.project_id
  role    = "roles/bigquery.admin"
  member  = "serviceAccount:${google_service_account.dataproc_sa.email}"
}

resource "google_project_iam_member" "dataproc_bigquery_connection_admin" {
  project = data.google_project.zipline.project_id
  role    = "roles/bigquery.connectionAdmin"
  member  = "serviceAccount:${google_service_account.dataproc_sa.email}"
}

resource "google_project_iam_member" "dataproc_bigquery_data_owner" {
  project = data.google_project.zipline.project_id
  role    = "roles/bigquery.dataOwner"
  member  = "serviceAccount:${google_service_account.dataproc_sa.email}"
}

# Bigtable Roles

resource "google_project_iam_member" "dataproc_bigtable_user" {
  project = data.google_project.zipline.project_id
  role    = "roles/bigtable.user"
  member  = "serviceAccount:${google_service_account.dataproc_sa.email}"
}

# Storage Roles

resource "google_project_iam_member" "dataproc_storage_object_admin" {
  project = data.google_project.zipline.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.dataproc_sa.email}"
}

# Autoscailing Policy

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

# Dataproc Cluster

resource "google_dataproc_cluster" "zipline_dataproc" {
  name   = "zipline-${lower(var.customer_name)}-cluster"
  region = var.region

  cluster_config {
    master_config {
      num_instances = 1
      machine_type  = "n2-highmem-64"
      disk_config {
        boot_disk_type    = "pd-standard"
        boot_disk_size_gb = 1024
      }
    }
    worker_config {
      machine_type = "n2-highmem-32"
      disk_config {
        boot_disk_type    = "pd-standard"
        boot_disk_size_gb = 1024
      }
    }

    initialization_action {
      script = "gs://zipline-jars/copy_java_security.sh"
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
        "https://www.googleapis.com/auth/cloud.useraccounts.readonly",
        "https://www.googleapis.com/auth/devstorage.read_write",
        "https://www.googleapis.com/auth/logging.write",
      ]
      subnetwork = var.dataproc_subnetwork
      tags       = var.dataproc_tags
      metadata = {
        hive-version           = "3.1.2",
        SPARK_BQ_CONNECTOR_URL = "gs://spark-lib/bigquery/spark-3.5-bigquery-0.42.1.jar",
      }
      internal_ip_only = true
    }
    software_config {
      image_version = "2.2.50-debian12"
      optional_components = [
        "FLINK",
        "JUPYTER",
      ]
      override_properties = {
        "flink:env.java.opts.client" = "-Djava.net.preferIPv4Stack=true -Djava.security.properties=/etc/flink/conf/java.security"
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