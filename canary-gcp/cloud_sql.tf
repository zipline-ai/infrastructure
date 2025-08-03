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

resource "google_sql_database_instance" "orchestration-instance" {
  database_version = "POSTGRES_16"
  name             = "orchestration-instance"
  region           = var.region
  settings {
    tier    = "db-g1-small"
    edition = "ENTERPRISE"

    database_flags {
      name  = "max_connections"
      value = "200" # Temporal needs at least 100 connections
    }
  }
  lifecycle {
    prevent_destroy = true
    ignore_changes = [settings]
  }
}

resource "google_sql_database" "orchestration-database" {
  name     = "execution-info"
  instance = google_sql_database_instance.orchestration-instance.name
  lifecycle {
    prevent_destroy = true
  }
}

# Create secrets for database credentials
resource "google_secret_manager_secret" "db_password" {
  secret_id = "zipline-db-password"
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

resource "google_secret_manager_secret_iam_member" "db_password_access" {
  secret_id = google_secret_manager_secret.db_password.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.cloud_run_service_account.email}"
}

resource "google_sql_user" "locker" {
  instance = google_sql_database_instance.orchestration-instance.name
  name     = "locker_user"
  password = random_password.db_password.result
}

resource "google_sql_database_instance" "temporal-instance" {
  database_version = "POSTGRES_16"
  name             = "temporal-instance"
  region           = var.region
  settings {
    tier    = "db-g1-small"
    edition = "ENTERPRISE"

    database_flags {
      name  = "max_connections"
      value = "200" # Temporal needs at least 100 connections
    }
  }
  lifecycle {
    prevent_destroy = true
    ignore_changes = [settings]
  }
}

resource "google_sql_database" "temporal-database" {
  instance = google_sql_database_instance.temporal-instance.name
  name     = "temporal"
}

resource "google_sql_user" "temporal_locker" {
  instance = google_sql_database_instance.temporal-instance.name
  name     = "locker_user"
  password = random_password.db_password.result
}
