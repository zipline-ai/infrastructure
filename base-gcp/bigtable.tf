resource "google_bigtable_instance" "zipline_bigtable_instance" {
  name = "zipline-${var.name}-bigtable"
  cluster {
    cluster_id   = "zipline-${var.name}-bigtable-cluster"
    zone         = var.zone
    storage_type = "HDD"
  }
  lifecycle {
    prevent_destroy = true
  }
}

resource "google_bigtable_table" "zipline_data_table" {
  name = "zipline-${var.name}-data-table"
  instance_name = google_bigtable_instance.zipline_bigtable_instance.name

}