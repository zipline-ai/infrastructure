resource "google_monitoring_dashboard" "zipline_bigtable" {
  project        = data.google_project.zipline.project_id
  dashboard_json = file("${path.module}/dashboards/BigTable.json")
}

resource "google_monitoring_dashboard" "zipline_flink_streaming" {
  project        = data.google_project.zipline.project_id
  dashboard_json = file("${path.module}/dashboards/Flink.json")
}
