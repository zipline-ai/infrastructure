data "google_project" "zipline" {
}


resource "google_project_service" "bigtable_admin" {
  project = data.google_project.zipline.project_id
  service = "bigtableadmin.googleapis.com"
}

resource "google_project_iam_member" "personnel_bigtable" {
    project = data.google_project.zipline.project_id
    role    = "roles/bigtable.admin"
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