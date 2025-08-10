resource "google_project_service" "cloud_sql" {
  service = "sqladmin.googleapis.com"

  disable_dependent_services = false
  disable_on_destroy         = false
}

resource "google_project_service" "secrets" {
  service = "secretmanager.googleapis.com"

  disable_dependent_services = false
  disable_on_destroy         = false
}

# Create secrets for database credentials
resource "google_secret_manager_secret" "db_password" {
  secret_id = "${var.customer_name}-zipline-db-password"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db_password.result
}

resource "random_password" "db_password" {
  length  = 16
  special = true
}


resource "google_sql_database_instance" "temporal_instance" {
  database_version = "POSTGRES_16"
  name             = "${var.customer_name}-zipline-temporal-instance"
  region           = var.region

  settings {
    tier    = "db-g1-small"
    edition = "ENTERPRISE"

    ip_configuration {
      ipv4_enabled    = true
      private_network = google_compute_network.zipline_vpc.id
    }

    database_flags {
      name  = "max_connections"
      value = "200"
    }
  }

  depends_on = [
    google_project_service.cloud_sql,
    google_service_networking_connection.private_vpc_connection
  ]

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_sql_database" "temporal_database" {
  name     = "temporal"
  instance = google_sql_database_instance.temporal_instance.name
  lifecycle {
    prevent_destroy = true
  }
}

resource "google_sql_user" "temporal_user" {
  instance = google_sql_database_instance.temporal_instance.name
  name     = "temporal_user"
  password = random_password.db_password.result
}


resource "google_sql_database_instance" "orchestration_instance" {
  database_version = "POSTGRES_16"
  name             = "${var.customer_name}-zipline-orchestration-instance"
  region           = var.region
  settings {
    tier    = "db-g1-small"
    edition = "ENTERPRISE"

    ip_configuration {
      ipv4_enabled    = true
      private_network = google_compute_network.zipline_vpc.id
    }

    database_flags {
      name  = "max_connections"
      value = "200" # Temporal needs at least 100 connections
    }
  }
  lifecycle {
    prevent_destroy = true
  }
  depends_on = [google_service_networking_connection.private_vpc_connection]
}

resource "google_sql_database" "orchestration_database" {
  name     = "execution-info"
  instance = google_sql_database_instance.orchestration_instance.name
  lifecycle {
    prevent_destroy = true
  }
}

resource "google_sql_user" "orchestration_user" {
  instance = google_sql_database_instance.orchestration_instance.name
  name     = "locker_user"
  password = random_password.db_password.result
}

resource "google_secret_manager_secret_iam_member" "db_password_access" {
  secret_id = google_secret_manager_secret.db_password.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "group:${var.personnel_email}"
}