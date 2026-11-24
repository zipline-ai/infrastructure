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

  depends_on = [google_project_service.required]
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
# Auth secret: the customer creates it and its value outside Terraform and sets
# gcp.auth_secret_id. Existing stacks created an empty container here; keep it
# (and any out-of-band versions) while dropping it from state.
# ---------------------------------------------------------------------------

removed {
  from = google_secret_manager_secret.auth
  lifecycle {
    destroy = false
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

  # Normalize bare IDs and project/secret pairs before deduplication.
  # These identities are also Terraform instance keys; see the README migration.
  secret_ids_to_grant = distinct([for ref in compact(concat(
    local.auth_enabled ? [local.auth_secret_id] : [],
    try(local.cloud_args.extra_secret_ids, []),
    try(var.orchestration.agents.enable, false) ? compact([
      try(var.orchestration.agents.anthropic_api_key_remote_ref.key, ""),
      try(var.orchestration.agents.openai_api_key_remote_ref.key, ""),
      try(var.orchestration.agents.gemini_api_key_remote_ref.key, ""),
    ]) : [],
    trimspace(try(var.orchestration.conf_repo.url, "")) == "" ? [] : compact([
      try(var.orchestration.conf_repo.github_token_remote_ref.key, ""),
      try(var.orchestration.conf_repo.github_client_secret_remote_ref.key, ""),
    ]),
    local.extra_external_secret_ids,
  )) : length(split("/", ref)) == 2 ? "projects/${split("/", ref)[0]}/secrets/${split("/", ref)[1]}" : (strcontains(ref, "/") ? ref : "projects/${local.cloud_args.project_id}/secrets/${ref}")])
}

resource "google_secret_manager_secret_iam_member" "orchestration_extras" {
  for_each = toset(local.secret_ids_to_grant)

  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.orchestration.email}"

  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret_iam_member" "eso_extras" {
  for_each = toset(local.secret_ids_to_grant)

  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.external_secrets.email}"

  depends_on = [google_project_service.required]
}
