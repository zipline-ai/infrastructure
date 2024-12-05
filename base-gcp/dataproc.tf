resource "google_service_account" "dataproc_sa" {
  account_id   = "dataproc"
  display_name = "Dataproc SA"

}

resource "google_dataproc_cluster" "zipline-dataproc" {
  name   = "zipline-${var.name}-cluster"
  region = var.region

  cluster_config {
    master_config {
      num_instances = 1
      machine_type  = "e2-standard-2"
    }
    worker_config {
      num_instances = 2
      machine_type = "m2-ultramem-208"
    }
    gce_cluster_config {
      service_account = google_service_account.dataproc_sa.email
      service_account_scopes = [
        "cloud-platform"
      ]
    }
  }
}