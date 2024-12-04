resource "google_bigtable_instance" "zipline-bigtable" {
  name = "zipline-${var.name}-bigtable"
  cluster {
    cluster_id   = "zipline-${var.name}-bigtable-cluster"
    zone       = var.zone
    storage_type = "HDD"
  }
  lifecycle {
    prevent_destroy = true
  }
}

resource "google_bigtable_table" "data-bigtable" {
  name = "zipline-${var.name}-data-table"
  instance_name = google_bigtable_instance.zipline-bigtable.name

}