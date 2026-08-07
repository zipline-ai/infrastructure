resource "random_password" "database" {
  length  = 32
  special = true
}

resource "google_secret_manager_secret" "database_credentials" {
  project             = local.project_id
  secret_id           = local.database_credentials_secret_name
  deletion_protection = !local.cloud_args.secret_force_destroy

  replication {
    auto {}
  }

  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret_version" "database_credentials" {
  secret = google_secret_manager_secret.database_credentials.id
  secret_data = jsonencode({
    username = local.cloud_args.database_username
    password = random_password.database.result
  })
}

resource "google_secret_manager_secret" "auth" {
  for_each = local.cloud_args.auth_secret_values

  project             = local.project_id
  secret_id           = "${local.name_prefix}-${replace(each.key, "_", "-")}"
  deletion_protection = !local.cloud_args.secret_force_destroy

  replication {
    auto {}
  }

  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret_version" "auth" {
  for_each = local.cloud_args.auth_secret_values

  secret      = google_secret_manager_secret.auth[each.key].id
  secret_data = each.value
}

resource "google_secret_manager_secret_iam_member" "database_accessor" {
  for_each = toset(["orchestration"])

  project   = local.project_id
  secret_id = google_secret_manager_secret.database_credentials.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.workload[each.value].email}"
}

resource "google_secret_manager_secret_iam_member" "auth_accessor" {
  for_each = {
    for item in flatten([
      for secret_key, secret_id in local.configured_auth_secret_ids : [
        for workload in ["orchestration"] : {
          key       = "${secret_key}:${workload}"
          secret_id = secret_id
          workload  = workload
        }
      ]
    ]) : item.key => item
  }

  project   = local.project_id
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.workload[each.value.workload].email}"
}
