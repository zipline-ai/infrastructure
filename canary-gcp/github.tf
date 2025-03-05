# This file is used to create a workload identity pool for Github Actions

data "google_project" "internal_project" {
}

# This allows Github Actions to authenticate to GCP and perform actions
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-actions"
  display_name              = "GitHub Workload Identity Pool"
  description               = "Workload Identity Pool for GitHub Actions"
}

# This creates a workload identity pool provider for Github Actions
resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  display_name                       = "Zipline Github Actions"
  attribute_mapping = {
    "attribute.aud"        = "assertion.aud"
    "attribute.actor"      = "assertion.actor"
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
  }
  attribute_condition = <<EOT
      assertion.repository_owner == "zipline-ai"
    EOT
  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
  depends_on = [
    google_iam_workload_identity_pool.github
  ]
}

resource "google_service_account" "github" {
  account_id   = "github-actions"
  display_name = "Zipline Github Actions"
}

resource "google_project_iam_member" "service_account_big_query" {
  project = data.google_project.internal_project.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.github.email}"
}