locals {
  workload_identity_bindings = merge([
    for workload, service_account in local.workload_service_accounts : {
      for kubernetes_service_account in service_account.kubernetes_service_accounts :
      "${workload}:${kubernetes_service_account}" => {
        workload                   = workload
        kubernetes_service_account = kubernetes_service_account
      }
    }
  ]...)

  workload_project_roles = merge([
    for workload, service_account in local.workload_service_accounts : {
      for role in service_account.roles :
      "${workload}:${role}" => {
        workload = workload
        role     = role
      }
    }
  ]...)
}

resource "google_service_account" "workload" {
  for_each = local.workload_service_accounts

  project      = local.project_id
  account_id   = each.value.account_id
  display_name = "${local.name_prefix} ${each.key} workload"

  depends_on = [google_project_service.required]
}

resource "google_service_account" "gke_nodes" {
  project      = local.project_id
  account_id   = "${substr(local.name_prefix, 0, 15)}-gke-${substr(sha1(local.name_prefix), 0, 8)}"
  display_name = "${local.name_prefix} GKE nodes"

  depends_on = [google_project_service.required]
}

resource "google_project_iam_member" "gke_nodes" {
  for_each = toset([
    "roles/artifactregistry.reader",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
  ])

  project = local.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_service_account_iam_member" "workload_identity" {
  for_each = local.workload_identity_bindings

  service_account_id = google_service_account.workload[each.value.workload].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${local.project_id}.svc.id.goog[${each.value.kubernetes_service_account}]"
}

resource "google_project_iam_member" "workload" {
  for_each = local.workload_project_roles

  project = local.project_id
  role    = each.value.role
  member  = "serviceAccount:${google_service_account.workload[each.value.workload].email}"
}
