provider "google" {
  project = local.cloud_args.project_id
  region  = local.cloud_args.region
}

provider "google-beta" {
  project = local.cloud_args.project_id
  region  = local.cloud_args.region
}

data "google_client_config" "default" {}

# Build the k8s providers from the running cluster. Auth via exec +
# gke-gcloud-auth-plugin — a static access_token expires after an hour and will
# abort a slow apply (chart install + SQL + Bigtable in one graph). See §5.2.
provider "kubernetes" {
  host                   = "https://${google_container_cluster.main.endpoint}"
  cluster_ca_certificate = base64decode(google_container_cluster.main.master_auth[0].cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "gke-gcloud-auth-plugin"
  }
}

provider "helm" {
  kubernetes {
    host                   = "https://${google_container_cluster.main.endpoint}"
    cluster_ca_certificate = base64decode(google_container_cluster.main.master_auth[0].cluster_ca_certificate)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "gke-gcloud-auth-plugin"
    }
  }
}
