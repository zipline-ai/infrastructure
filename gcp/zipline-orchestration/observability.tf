resource "google_project_iam_member" "workload_monitoring_viewer" {
  for_each = toset(["orchestration"])

  project = local.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.workload[each.value].email}"
}
