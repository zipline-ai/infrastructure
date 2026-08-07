resource "google_compute_global_address" "private_services" {
  count = local.create_private_service_access ? 1 : 0

  project       = local.network_project_id
  name          = "${local.name_prefix}-private-services"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = local.cloud_args.private_service_prefix_length
  network       = local.network_self_link

  depends_on = [google_project_service.required]
}

resource "google_service_networking_connection" "private_services" {
  count = local.create_private_service_access ? 1 : 0

  network                 = local.network_self_link
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_services[0].name]
}

resource "google_sql_database_instance" "main" {
  project             = local.project_id
  name                = local.database_instance_name
  region              = local.region
  database_version    = local.cloud_args.database_version
  deletion_protection = local.cloud_args.database_deletion_protection

  settings {
    tier              = local.cloud_args.database_tier
    availability_type = local.cloud_args.database_availability_type
    disk_size         = local.cloud_args.database_disk_size
    disk_autoresize   = true

    backup_configuration {
      enabled                        = local.cloud_args.database_backup_enabled
      point_in_time_recovery_enabled = local.cloud_args.database_backup_enabled
    }

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = local.network_self_link
      enable_private_path_for_google_cloud_services = true
    }
  }

  depends_on = [google_service_networking_connection.private_services]
}

resource "google_sql_database" "main" {
  project  = local.project_id
  name     = local.database_name
  instance = google_sql_database_instance.main.name
}

resource "google_sql_user" "main" {
  project  = local.project_id
  name     = local.cloud_args.database_username
  instance = google_sql_database_instance.main.name
  password = random_password.database.result
}
