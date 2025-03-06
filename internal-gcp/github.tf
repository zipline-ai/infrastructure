# This file is used to create a workload identity pool for Github Actions

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

# This creates a service account for Github Actions
resource "google_service_account" "github" {
  account_id   = "github-actions"
  display_name = "Zipline Github Actions"
}

data "google_project" "internal_project" {
}

resource "google_service_account_iam_member" "github_actions" {
  service_account_id = google_service_account.github.id
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/zipline-ai/chronon"
  depends_on = [
    google_iam_workload_identity_pool_provider.github
  ]
}

data "google_service_account" "canary_github" {
  project    = "canary-443022"
  account_id = "github-actions"
}

resource "google_project_iam_member" "canary_service_account_storage" {
  project = data.google_project.internal_project.project_id
  role    = "roles/storage.objectUser"
  member  = "serviceAccount:${data.google_service_account.canary_github.email}"
}


resource "google_project_iam_member" "service_account_storage" {
  project = data.google_project.internal_project.project_id
  role    = "roles/storage.objectUser"
  member  = "serviceAccount:${google_service_account.github.email}"
}

# Enable IAM credentials API so that the service account can impersonate other service accounts
resource "google_project_service" "iamcredentials_api" {
  project = data.google_project.internal_project.project_id
  service = "iamcredentials.googleapis.com"
}