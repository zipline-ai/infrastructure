resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"

  lifecycle {
    ignore_changes = [override_special]
  }
}

resource "google_sql_database_instance" "zipline" {
  name                = "${local.name_prefix}-zipline-orch-instance"
  database_version    = local.cloud_args.database_version
  region              = local.cloud_args.region
  deletion_protection = local.cloud_args.database_deletion_protection

  settings {
    tier              = local.cloud_args.cloudsql_tier
    edition           = local.cloud_args.cloudsql_edition
    availability_type = local.cloud_args.cloudsql_availability_type
    disk_size         = local.cloud_args.cloudsql_disk_size
    disk_type         = "PD_SSD"
    disk_autoresize   = true
    # Autoresize ceiling (0 = unlimited). The plan sets a 100 GiB default.
    disk_autoresize_limit = local.cloud_args.cloudsql_disk_autoresize_limit

    ip_configuration {
      ipv4_enabled    = false
      private_network = local.network_self_link
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = "08:00" # 02:00 CST / 03:00 CDT UTC
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = local.cloud_args.cloudsql_backup_retention_days
        retention_unit   = "COUNT"
      }
    }

    database_flags {
      name = "max_connections"
      # Cloud SQL auto-sizes from instance memory; changing it forces a
      # restart (regional = failover). Set once, deliberately.
      value = tostring(local.cloud_args.cloudsql_max_connections)
    }

    maintenance_window {
      day          = 6 # Saturday
      hour         = 8 # 02:00 CST (UTC-6)
      update_track = "stable"
    }

    deny_maintenance_period {
      # Overridable; the default covers a two-week launch window. The user
      # can shorten by setting an earlier end_date.
      start_date = local.cloud_args.database_deny_maintenance_start_date
      end_date   = local.cloud_args.database_deny_maintenance_end_date
      time       = "00:00:00"
    }

    dynamic "insights_config" {
      for_each = local.cloud_args.cloudsql_query_insights ? [1] : []
      content {
        query_insights_enabled = true
      }
    }
  }

  encryption_key_name = local.cloud_args.cmek_key_id != "" ? local.cloud_args.cmek_key_id : null

  depends_on = [
    google_service_networking_connection.psa,
  ]
}

resource "google_sql_database" "execution_info" {
  name     = local.cloud_args.database_name
  instance = google_sql_database_instance.zipline.name
}

resource "google_sql_user" "zipline" {
  name     = local.cloud_args.database_username
  instance = google_sql_database_instance.zipline.name
  password = random_password.db_password.result
}
