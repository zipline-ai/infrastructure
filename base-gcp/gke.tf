# Enable additional APIs needed for GKE
resource "google_project_service" "container_api" {
  service                    = "container.googleapis.com"
  disable_dependent_services = false
  disable_on_destroy         = false
}

# GKE Autopilot Cluster
resource "google_container_cluster" "orchestration_cluster" {
  name     = "${var.customer_name}-zipline-cluster"
  location = var.region
  project  = data.google_project.zipline.project_id

  # Enable Autopilot
  enable_autopilot = true

  # Use existing VPC
  network    = google_compute_network.zipline_vpc.name
  subnetwork = google_compute_subnetwork.zipline_subnet.name

  # IP allocation for pods and services
  ip_allocation_policy {
    cluster_secondary_range_name  = "gke-pods"
    services_secondary_range_name = "gke-services"
  }

  # Private cluster configuration
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  # Workload Identity for secure pod authentication
  workload_identity_config {
    workload_pool = "${data.google_project.zipline.project_id}.svc.id.goog"
  }

  dns_config {
    cluster_dns        = "CLOUD_DNS"
    cluster_dns_scope  = "CLUSTER_SCOPE"
    cluster_dns_domain = "cluster.local"
  }

  depends_on = [
    google_project_service.container_api,
    google_service_networking_connection.private_vpc_connection
  ]
}

# Get cluster credentials for Kubernetes provider
data "google_client_config" "default" {}

# Configure Kubernetes provider
provider "kubernetes" {
  host                   = "https://${google_container_cluster.orchestration_cluster.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.orchestration_cluster.master_auth[0].cluster_ca_certificate)
}

# Configure Helm provider
provider "helm" {
  kubernetes = {
    host                   = "https://${google_container_cluster.orchestration_cluster.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(google_container_cluster.orchestration_cluster.master_auth[0].cluster_ca_certificate)
  }
}

###########################################################
# Service Accounts and IAM Bindings

# Google Service Account for Temporal
resource "google_service_account" "temporal_gsa" {
  account_id   = "temporal-sa"
  display_name = "Zipline Temporal Service Account"
  project      = data.google_project.zipline.project_id
}

# Bind Kubernetes SA to Google SA for Temporal
resource "google_service_account_iam_binding" "temporal_workload_identity" {
  service_account_id = google_service_account.temporal_gsa.name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    "serviceAccount:${data.google_project.zipline.project_id}.svc.id.goog[zipline-system/temporal-sa]"
  ]
}

# Grant Cloud SQL access to the Temporal service account
resource "google_project_iam_member" "temporal_cloudsql" {
  project = data.google_project.zipline.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.temporal_gsa.email}"
}

# Google Service Account for Orchestration Hub and Worker
resource "google_service_account" "orchestration_sa" {
  account_id   = "orchestration-sa"
  display_name = "Zipline Orchestration Service Account"
  project      = data.google_project.zipline.project_id
}

# Bind Kubernetes SA to Google SA for Orchestration
resource "google_service_account_iam_member" "orchestration_workload_identity" {
  service_account_id = google_service_account.orchestration_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${data.google_project.zipline.project_id}.svc.id.goog[zipline-system/orchestration-sa]"
}

# Grant various permissions to orchestration service account
resource "google_project_iam_member" "orchestration_cloudsql" {
  project = data.google_project.zipline.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.orchestration_sa.email}"
}

resource "google_project_iam_member" "orchestration_bigtable" {
  project = data.google_project.zipline.project_id
  role    = "roles/bigtable.user"
  member  = "serviceAccount:${google_service_account.orchestration_sa.email}"
}

resource "google_project_iam_member" "orchestration_dataproc" {
  project = data.google_project.zipline.project_id
  member  = "serviceAccount:${google_service_account.orchestration_sa.email}"
  role    = "roles/dataproc.editor"
}

resource "google_project_iam_member" "orchestration_storage" {
  project = data.google_project.zipline.project_id
  member  = "serviceAccount:${google_service_account.orchestration_sa.email}"
  role    = "roles/storage.objectAdmin"
}

resource "google_project_iam_member" "orchestration_monitoring" {
  project = data.google_project.zipline.project_id
  member  = "serviceAccount:${google_service_account.orchestration_sa.email}"
  role    = "roles/monitoring.editor"
}

###########################################################
# Static IP Addresses for Load Balancers

resource "google_compute_global_address" "orchestration_ui_ip" {
  name = "zipline-orchestration-ui-ip"
}

resource "google_compute_global_address" "temporal_ui_ip" {
  name = "zipline-temporal-ui-ip"
}

resource "google_compute_global_address" "orchestration_hub_ip" {
  name = "zipline-orchestration-hub-ip"
}

###########################################################
# Deploy Zipline Orchestration using Helm

resource "helm_release" "zipline_orchestration" {
  name       = "zipline-orchestration"
  chart      = "../zipline-orchestration"  # Path to your local helm chart
  namespace  = "zipline-system"
  create_namespace = true

  values = [
    templatefile("${path.module}/helm-values.yaml.tpl", {
      customer_name = var.customer_name
      region = var.region
      project_id = data.google_project.zipline.project_id
      artifact_prefix = var.artifact_prefix
      topic_id = var.topic_id

      temporal_db_host = google_sql_database_instance.temporal_instance.private_ip_address
      temporal_db_username = google_sql_user.temporal_user.name
      temporal_db_password = google_secret_manager_secret_version.db_password.secret_data
      temporal_db_database = google_sql_database.temporal_database.name

      orchestration_db_host = google_sql_database_instance.orchestration_instance.private_ip_address
      orchestration_db_username = google_sql_user.orchestration_user.name
      orchestration_db_password = google_secret_manager_secret_version.db_password.secret_data
      orchestration_db_database = google_sql_database.orchestration_database.name

      bigtable_instance_id = google_bigtable_instance.zipline_bigtable_instance.name

      temporal_service_account = google_service_account.temporal_gsa.email
      orchestration_service_account = google_service_account.orchestration_sa.email

      orchestration_ui_ip = google_compute_global_address.orchestration_ui_ip.address
      temporal_ui_ip = google_compute_global_address.temporal_ui_ip.address
      orchestration_hub_ip = google_compute_global_address.orchestration_hub_ip.address

      zipline_ui_domain = var.zipline_ui_domain
      temporal_domain = var.temporal_domain
      hub_domain = var.hub_domain
    })
  ]

  depends_on = [
    google_container_cluster.orchestration_cluster,
    google_sql_database.temporal_database,
    google_sql_user.temporal_user,
    google_sql_database.orchestration_database,
    google_sql_user.orchestration_user,
    google_service_account_iam_member.orchestration_workload_identity,
    google_service_account_iam_binding.temporal_workload_identity,
    google_project_iam_member.orchestration_cloudsql,
    google_project_iam_member.temporal_cloudsql,
    google_project_iam_member.orchestration_dataproc,
    google_project_iam_member.orchestration_bigtable,
    google_project_iam_member.orchestration_monitoring,
    google_project_iam_member.orchestration_storage
  ]
}

###########################################################
# Outputs

output "orchestration_ui_ip" {
  value = google_compute_global_address.orchestration_ui_ip.address
  description = "Static IP address for the orchestration UI ingress"
}

output "temporal_ui_ip" {
  value = google_compute_global_address.temporal_ui_ip.address
  description = "Static IP address for the Temporal Web UI ingress"
}

output "orchestration_hub_ip" {
  value = google_compute_global_address.orchestration_hub_ip.address
  description = "Static IP address for the orchestration hub ingress"
}

output "orchestration_ui_https_url" {
  value = var.zipline_ui_domain != "" ? "https://${var.zipline_ui_domain}" : "https://${google_compute_global_address.orchestration_ui_ip.address}.nip.io"
  description = "HTTPS URL for the Zipline UI (This may take 15-60 minutes to be active)"
}

output "temporal_ui_https_url" {
  value = var.temporal_domain != "" ? "https://${var.temporal_domain}" : "https://${google_compute_global_address.temporal_ui_ip.address}.nip.io"
  description = "HTTPS URL for the Temporal Web UI (This may take 15-60 minutes to be active)"
}

output "orchestration_hub_https_url" {
  value = var.hub_domain != "" ? "https://${var.hub_domain}" : "https://${google_compute_global_address.orchestration_hub_ip.address}.nip.io"
  description = "HTTPS URL for the Zipline Hub (This may take 15-60 minutes to be active)"
}

locals {
  setup_instructions = <<-EOT
Zipline Orchestration Deployment Complete!

Static IP Addresses:
- Orchestration UI: ${google_compute_global_address.orchestration_ui_ip.address}
- Temporal UI: ${google_compute_global_address.temporal_ui_ip.address}
- Orchestration Hub: ${google_compute_global_address.orchestration_hub_ip.address}

${var.zipline_ui_domain != "" || var.temporal_domain != "" || var.hub_domain != "" ?
"DNS Setup Required:" : ""}
${var.zipline_ui_domain != "" ? "- Point ${var.zipline_ui_domain} A record to ${google_compute_global_address.orchestration_ui_ip.address}" : ""}
${var.temporal_domain != "" ? "- Point ${var.temporal_domain} A record to ${google_compute_global_address.temporal_ui_ip.address}" : ""}
${var.hub_domain != "" ? "- Point ${var.hub_domain} A record to ${google_compute_global_address.orchestration_hub_ip.address}" : ""}

Access URLs (available in 15-60 minutes):
- Zipline UI: ${var.zipline_ui_domain != "" ? "https://${var.zipline_ui_domain}" : "https://${google_compute_global_address.orchestration_ui_ip.address}.nip.io"}
- Temporal UI: ${var.temporal_domain != "" ? "https://${var.temporal_domain}" : "https://${google_compute_global_address.temporal_ui_ip.address}.nip.io"}
- Orchestration Hub: ${var.hub_domain != "" ? "https://${var.hub_domain}" : "https://${google_compute_global_address.orchestration_hub_ip.address}.nip.io"}

The Google-managed certificates will be automatically issued and renewed!
EOT
}

output "setup_instructions" {
  value = local.setup_instructions
}