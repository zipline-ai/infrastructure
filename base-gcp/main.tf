data "google_project" "zipline" {
}


resource "google_project_service" "bigtable_admin" {
  project = data.google_project.zipline.project_id
  service = "bigtableadmin.googleapis.com"
}

resource "google_project_service" "cloud_profiler" {
  project            = data.google_project.zipline.project_id
  service            = "cloudprofiler.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "monitoring" {
  project = data.google_project.zipline.project_id
  service = "monitoring.googleapis.com"
}

# Personnel Roles

resource "google_project_iam_member" "personnel_bigtable" {
  project = data.google_project.zipline.project_id
  role    = "roles/bigtable.user"
  member  = "group:${var.personnel_email}"
}

resource "google_project_iam_member" "personnel_logging" {
  project = data.google_project.zipline.project_id
  role    = "roles/logging.viewer"
  member  = "group:${var.personnel_email}"
}

resource "google_project_iam_member" "personnel_dataproc" {
  project = data.google_project.zipline.project_id
  role    = "roles/dataproc.editor"
  member  = "group:${var.personnel_email}"
}

resource "google_project_iam_member" "personnel_bigquery" {
  project = data.google_project.zipline.project_id
  role    = "roles/bigquery.user"
  member  = "group:${var.personnel_email}"
}

resource "google_project_iam_member" "personnel_bigquery_data" {
  project = data.google_project.zipline.project_id
  role    = "roles/bigquery.dataViewer"
  member  = "group:${var.personnel_email}"
}

resource "google_project_iam_member" "personnel_compute" {
  project = data.google_project.zipline.project_id
  role    = "roles/compute.admin"
  member  = "group:${var.personnel_email}"
}

resource "google_project_iam_member" "personnel_storage_admin" {
  project = data.google_project.zipline.project_id
  role    = "roles/storage.admin"
  member  = "group:${var.personnel_email}"
}

resource "google_project_iam_member" "personnel_storage_object_admin" {
  project = data.google_project.zipline.project_id
  role    = "roles/storage.objectAdmin"
  member  = "group:${var.personnel_email}"
}

resource "google_project_iam_member" "personnel_monitoring" {
  project = data.google_project.zipline.project_id
  role    = "roles/monitoring.admin"
  member  = "group:${var.personnel_email}"
}

resource "google_project_iam_member" "personnel_viewer" {
  project = data.google_project.zipline.project_id
  role    = "roles/viewer"
  member  = "group:${var.personnel_email}"
}