data "google_project" "zipline" {
}


resource "google_project_service" "bigtable_admin" {
  project = data.google_project.zipline.project_id
  service = "bigtableadmin.googleapis.com"
}