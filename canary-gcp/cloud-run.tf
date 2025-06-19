resource "google_artifact_registry_repository" "docker_hub_remote_repository" {
  format        = "docker"
  repository_id = "zipline-docker-hub-proxy"
  location      = var.region
  description = "Remote repository for Docker images from Docker Hub"
  remote_repository_config {
    description = "Proxy repository for ziplineai images on Docker Hub"
    docker_repository {
      public_repository = "DOCKER_HUB"
    }
  }
}

resource "google_cloud_run_service" "fetcher" {
  name     = "zipline-fetcher"
  location = var.region

  template {
    spec {
      containers {
        image = "${google_artifact_registry_repository.docker_hub_remote_repository.location}-docker.pkg.dev/${data.google_project.zipline.project_id}/${google_artifact_registry_repository.docker_hub_remote_repository.repository_id}/ziplineai/chronon-fetcher:v0.8.1"
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  depends_on = [
    google_artifact_registry_repository.docker_hub_remote_repository,
  ]
}