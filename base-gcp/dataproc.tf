resource "google_service_account" "dataproc_sa" {
  account_id   = "dataproc"
  display_name = "Dataproc SA"
}

data "google_project" "zipline" {
}

# Dataproc Roles

resource "google_project_iam_member" "dataproc_admin" {
  project           = data.google_project.zipline.project_id
  role              = "roles/dataproc.admin"
  member            = "serviceAccount:${google_service_account.dataproc_sa.email}"
}

resource "google_project_iam_member" "dataproc_service_agent" {
  project           = data.google_project.zipline.project_id
  role              = "roles/dataproc.serviceAgent"
  member            = "serviceAccount:${google_service_account.dataproc_sa.email}"
}

resource "google_project_iam_member" "dataproc_worker" {
  project           = data.google_project.zipline.project_id
  role              = "roles/dataproc.worker"
  member            = "serviceAccount:${google_service_account.dataproc_sa.email}"
}



# BigQuery Roles

resource "google_project_iam_member" "dataproc_bigquery_admin" {
  project           = data.google_project.zipline.project_id
  role              = "roles/bigquery.admin"
  member            = "serviceAccount:${google_service_account.dataproc_sa.email}"
}

resource "google_project_iam_member" "dataproc_bigquery_connection_admin" {
  project           = data.google_project.zipline.project_id
  role              = "roles/bigquery.connectionAdmin"
  member            = "serviceAccount:${google_service_account.dataproc_sa.email}"
}

resource "google_project_iam_member" "dataproc_bigquery_data_owner" {
  project           = data.google_project.zipline.project_id
  role              = "roles/bigquery.dataOwner"
  member            = "serviceAccount:${google_service_account.dataproc_sa.email}"
}

# Metastore Roles

resource "google_project_iam_member" "dataproc_metastore_admin" {
  project           = data.google_project.zipline.project_id
  role              = "roles/metastore.admin"
  member            = "serviceAccount:${google_service_account.dataproc_sa.email}"
}

resource "google_project_iam_member" "dataproc_metastore_editor" {
  project           = data.google_project.zipline.project_id
  role              = "roles/metastore.editor"
  member            = "serviceAccount:${google_service_account.dataproc_sa.email}"
}

resource "google_project_iam_member" "dataproc_metastore_mutate_admin" {
  project           = data.google_project.zipline.project_id
  role              = "roles/metastore.metadataMutateAdmin"
  member            = "serviceAccount:${google_service_account.dataproc_sa.email}"
}

resource "google_project_iam_member" "dataproc_metastore_metadata_editor" {
  project           = data.google_project.zipline.project_id
  role              = "roles/metastore.metadataEditor"
  member            = "serviceAccount:${google_service_account.dataproc_sa.email}"
}


resource "google_project_iam_member" "dataproc_metastore_federation_accessor" {
  project           = data.google_project.zipline.project_id
  role              = "roles/metastore.federationAccessor"
  member            = "serviceAccount:${google_service_account.dataproc_sa.email}"
}

# Bigtable Roles

resource "google_project_iam_member" "dataproc_bigtable_user" {
  project           = data.google_project.zipline.project_id
  role              = "roles/bigtable.user"
  member            = "serviceAccount:${google_service_account.dataproc_sa.email}"
}

# Dataproc Cluster

resource "google_dataproc_cluster" "zipline_dataproc" {
  name   = "zipline-${lower(var.name)}-cluster"
  region = var.region

  cluster_config {
    master_config {
      num_instances = 1
      machine_type  = "n2-highmem-64"
      disk_config {
        boot_disk_type = "pd-standard"
        boot_disk_size_gb = 30
      }
    }
    worker_config {
      num_instances = 2
      machine_type = "n2-highmem-32"
      disk_config {
        boot_disk_type = "pd-standard"
        boot_disk_size_gb = 30
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
      metadata = {
        proxy-uri = google_dataproc_metastore_federation.big_query_metastore_federation.endpoint_uri
        hive-version = "3.1.2",
        SPARK_BQ_CONNECTOR_URL = "gs://spark-lib/bigquery/spark-bigquery-with-dependencies_2.12-0.41.0.jar"
      }
    }
    software_config {
      image_version = "2.2.39-debian12"
      optional_components = [
        "FLINK",
        "DOCKER",
        "JUPYTER",
      ]
      override_properties = {
        "hive:hive.metastore.uris" = "thrift://localhost:9083",
        "hive:hive.metastore.warehouse.dir" = "gs://gcs-bucket-service-baaa-35549b5d-c533-479b-a846-486147487b0f/hive-warehouse"
      }
    }
    endpoint_config {
      enable_http_port_access = true
    }
    initialization_action {
      script = "gs://metastore-init-actions/metastore-grpc-proxy/metastore-grpc-proxy.sh"
    }
  }
  depends_on = [
    google_project_iam_member.dataproc_worker,
    google_project_iam_member.dataproc_service_agent,
    google_project_iam_member.dataproc_metastore_federation_accessor
  ]
}