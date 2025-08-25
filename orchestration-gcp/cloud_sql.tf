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
  secret_id = "${var.name_prefix}-zipline-db-password"
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
  name             = "${var.name_prefix}-zipline-temporal-instance"
  region           = var.region

  settings {
    tier    = "db-custom-8-30720"
    edition = "ENTERPRISE"

    ip_configuration {
      ipv4_enabled    = true
      private_network = var.vpc_id
    }

    database_flags {
      name  = "max_connections"
      value = "10000"
    }

    backup_configuration {
      enabled    = true
      start_time = "03:00" # UTC time for backup start
      location   = var.region
    }
  }

  depends_on = [
    google_project_service.cloud_sql,
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
  name             = "${var.name_prefix}-zipline-orchestration-instance"
  region           = var.region
  settings {
    tier    = "db-custom-8-30720"
    edition = "ENTERPRISE"

    ip_configuration {
      ipv4_enabled    = true
      private_network = var.vpc_id
    }

    database_flags {
      name  = "max_connections"
      value = "10000" # Temporal needs at least 100 connections
    }

    backup_configuration {
      enabled    = true
      start_time = "03:00" # UTC time for backup start
      location   = var.region
    }
  }
  lifecycle {
    prevent_destroy = true
  }
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