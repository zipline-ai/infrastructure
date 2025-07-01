resource "google_artifact_registry_repository" "docker_hub_remote_repository" {
  format        = "docker"
  repository_id = "zipline-docker-hub-proxy"
  location      = var.region
  description   = "Remote repository for Docker images from Docker Hub"
  remote_repository_config {
    description = "Proxy repository for ziplineai images on Docker Hub"
    docker_repository {
      public_repository = "DOCKER_HUB"
    }
  }
}

resource "google_service_account" "cloud_run_service_account" {
  account_id   = "zipline-cloud-run-sa"
  display_name = "Zipline Cloud Run Service Account"
  project      = data.google_project.zipline.project_id
}

resource "google_project_iam_member" "cloud_run_service_account_role" {
  project = data.google_project.zipline.project_id
  member  = "serviceAccount:${google_service_account.cloud_run_service_account.email}"
  role    = "roles/dataproc.editor"
}


resource "google_cloud_run_v2_service" "orchestrator" {
  name     = "zipline-orchestrator"
  location = var.region

  template {
    spec {
      containers {
        image = "${google_artifact_registry_repository.docker_hub_remote_repository.location}-docker.pkg.dev/${data.google_project.zipline.project_id}/${google_artifact_registry_repository.docker_hub_remote_repository.repository_id}/ziplineai/chronon-orchestrator:v0.0.1"
      }
    }
    service_account = google_service_account.cloud_run_service_account.email
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  depends_on = [
    google_artifact_registry_repository.docker_hub_remote_repository,
  ]
}