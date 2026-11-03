# ---------------------------------------------------------------------------
# DB credentials: TF both creates the container and writes the version, since
# the password is generated inline (database.tf random_password).
# ---------------------------------------------------------------------------

resource "google_secret_manager_secret" "db_credentials" {
  secret_id = "${local.name_prefix}-zipline-db-password"

  replication {
    auto {
      dynamic "customer_managed_encryption" {
        for_each = local.cloud_args.cmek_key_id != "" ? [1] : []
        content {
          kms_key_name = local.cloud_args.cmek_key_id
        }
      }
    }
  }
}

resource "google_secret_manager_secret_version" "db_credentials" {
  secret = google_secret_manager_secret.db_credentials.id
  secret_data = jsonencode({
    username = local.cloud_args.database_username
    password = random_password.db_password.result
  })
}

resource "google_secret_manager_secret_iam_member" "db_credentials_orchestration" {
  secret_id = google_secret_manager_secret.db_credentials.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.orchestration.email}"
}

resource "google_secret_manager_secret_iam_member" "db_credentials_eso" {
  secret_id = google_secret_manager_secret.db_credentials.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.external_secrets.email}"
}

# ---------------------------------------------------------------------------
# Auth secret container (§7.4). One JSON secret with five/six keys for all SSO
# providers. TF creates the container only; values live out of band
# (`gcloud secrets versions add`). Grants are added when auth.enabled=true
# AND auth_secret_id resolves to a secret in THIS project.
# ---------------------------------------------------------------------------

locals {
  auth_secret_in_project = local.auth_enabled && (
    can(regex("^projects/${local.cloud_args.project_id}/secrets/[^/]+$", local.auth_secret_id)) ||
    can(regex("^[A-Za-z0-9_-]+$", local.auth_secret_id))
  )
  # Short name used to resolve this project's secret-manager resource IDs. For a
  # fully-qualified ref (projects/<p>/secrets/<name>), take the trailing
  # segment; for a bare id, use it as-is. Only consulted when auth_secret_in_project.
  auth_secret_short_name = local.auth_secret_in_project ? regex("[^/]+$", local.auth_secret_id) : ""
}

resource "google_secret_manager_secret" "auth" {
  count = local.auth_enabled && local.auth_secret_in_project ? 1 : 0

  secret_id = local.auth_secret_short_name

  replication {
    auto {
      dynamic "customer_managed_encryption" {
        for_each = local.cloud_args.cmek_key_id != "" ? [1] : []
        content {
          kms_key_name = local.cloud_args.cmek_key_id
        }
      }
    }
  }

  lifecycle {
    # Preserves out-of-band version writes (gcloud secrets versions add) when
    # the container is managed here. TF won't recreate the container just
    # because versions appeared.
    prevent_destroy = true
  }
}

# ---------------------------------------------------------------------------
# Grants for the auth secret (and any extras in extra_secret_ids / derived
# from extra_external_secrets). orchestration + ESO need secretAccessor.
# ---------------------------------------------------------------------------

locals {
  # Harvest Secret Manager ids referenced by extra_external_secrets so a tfvars
  # ExternalSecret declaration carries its own grant (parity with AWS §7.3).
  extra_external_secret_ids = distinct(compact(flatten([
    for external_secret in try(local.cloud_args.extra_external_secrets, []) : [
      for item in try(external_secret.spec.data, []) : tostring(try(item.remoteRef.key, ""))
      if can(regex("^projects/[^/]+/secrets/[^/]+$", tostring(try(item.remoteRef.key, "")))) ||
      can(regex("^[A-Za-z0-9_-]+$", tostring(try(item.remoteRef.key, ""))))
    ]
  ])))

  # Combined list of secret ids the orchestration GSA + ESO need accessor on.
  secret_ids_to_grant = distinct(compact(concat(
    local.auth_enabled ? [local.auth_secret_id] : [],
    try(local.cloud_args.extra_secret_ids, []),
    trimspace(try(var.orchestration.conf_repo.url, "")) == "" ? [] : compact([
      try(var.orchestration.conf_repo.github_token_remote_ref.key, ""),
      try(var.orchestration.conf_repo.github_client_secret_remote_ref.key, ""),
    ]),
    local.extra_external_secret_ids,
  )))
}

resource "google_secret_manager_secret_iam_member" "orchestration_extras" {
  for_each = toset(local.secret_ids_to_grant)

  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.orchestration.email}"
}

resource "google_secret_manager_secret_iam_member" "eso_extras" {
  for_each = toset(local.secret_ids_to_grant)

  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.external_secrets.email}"
}
