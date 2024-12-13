resource "google_bigtable_instance" "zipline_bigtable_instance" {
  name = "zipline-${lower(var.name)}-instance"
  cluster {
    cluster_id   = "zipline-${lower(var.name)}"
    zone         = var.zone
    storage_type = "HDD"
  }
  lifecycle {
    prevent_destroy = true
  }
}

resource "google_bigtable_table" "groupby_batch" {
  instance_name = google_bigtable_instance.zipline_bigtable_instance.name
  name = "GROUPBY_BATCH"
}

resource "google_bigtable_table" "groupby_streaming" {
  instance_name = google_bigtable_instance.zipline_bigtable_instance.name
  name = "GROUPBY_STREAMING"
}

resource "google_bigtable_table" "tile_summaries" {
  instance_name = google_bigtable_instance.zipline_bigtable_instance.name
  name = "TILE_SUMMARIES"
}

resource "google_bigtable_table" "chronon_metadata" {
  instance_name = google_bigtable_instance.zipline_bigtable_instance.name
  name = "CHRONON_METADATA"
}

resource "google_bigtable_table" "entity_keys_by_team" {
  instance_name = google_bigtable_instance.zipline_bigtable_instance.name
  name = "ENTITY_KEYS_BY_TEAM"
}