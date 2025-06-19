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
      machine_type  = "n2-highmem-64"
      disk_config {
        boot_disk_type    = "pd-standard"
        boot_disk_size_gb = 1024
      }
    }
    worker_config {
      machine_type = "n1-highmem-16"
      disk_config {
        boot_disk_type    =  "pd-standard"
        boot_disk_size_gb =  64
        num_local_ssds    =  2
      }
    }

    initialization_action {
      script = "gs://zipline-jars/copy_java_security.sh"
    }

    # Add initialization action to install ops agent for Flink metrics
    initialization_action {
      script = "gs://zipline-jars/opsagent_flink_install.sh"
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

output "dataproc_service_account_id" {
  value = "${google_service_account.dataproc_sa.id}"
}

resource "local_file" "dataproc_access_script" {
  filename = "${path.module}/access_dataproc_ui.sh"
  content = <<-EOT
#!/bin/bash
# Auto-generated script for accessing Dataproc Web UIs
# Cluster: ${google_dataproc_cluster.zipline_dataproc.name}

PROJECT_ID="${data.google_project.zipline.project_id}"
MASTER_NODE="${google_dataproc_cluster.zipline_dataproc.cluster_config.0.master_config.0.instance_names[0]}"
ZONE="${google_dataproc_cluster.zipline_dataproc.cluster_config.0.gce_cluster_config.0.zone}"

echo "Setting up SSH tunnel to Dataproc master node..."
echo "Web UIs will be available at:"
echo " - YARN ResourceManager: http://localhost:8088"
echo " - HDFS NameNode: http://localhost:9870"
echo " - Spark History Server: http://localhost:18080"
echo " - Jupyter: http://localhost:8123 (if enabled)"
echo ""
echo "Press Ctrl+C to stop the tunnel when done."

gcloud compute ssh $MASTER_NODE \
  --project $PROJECT_ID \
  --zone $ZONE \
  --tunnel-through-iap \
  -- -L 8088:localhost:8088 \
     -L 9870:localhost:9870 \
     -L 18080:localhost:18080 \
     -L 8123:localhost:8123 \
     -L 8888:localhost:8888
EOT

  file_permission = "0755" # Make the script executable
}

output "access_script_path" {
  value = local_file.dataproc_access_script.filename
}