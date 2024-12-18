resource "google_bigtable_instance" "zipline_bigtable_instance" {
  name = "zipline-${lower(var.name)}-instance"
  cluster {
    cluster_id   = "zipline-${lower(var.name)}"
    zone         = var.zone
    storage_type = "HDD"
    autoscaling_config {
      cpu_target = 50
      max_nodes  = 10
      min_nodes  = 2
    }
  }
  lifecycle {
    prevent_destroy = true
  }
}

resource "google_bigtable_table" "groupby_batch" {
  instance_name = google_bigtable_instance.zipline_bigtable_instance.name
  name = "GROUPBY_BATCH"
  column_family {
    family = "cf"
  }
}

resource "google_bigtable_gc_policy" "groupby_batch_gc_policy" {
  instance_name = google_bigtable_instance.zipline_bigtable_instance.name
  table = google_bigtable_table.groupby_batch.name
  column_family = "cf"

  mode = "UNION"
  max_age {
    duration = "120h"
  }
  max_version {
    number = 10000
  }
}

resource "google_bigtable_table" "groupby_streaming" {
  instance_name = google_bigtable_instance.zipline_bigtable_instance.name
  name = "GROUPBY_STREAMING"
  column_family {
    family = "cf"
  }
}

resource "google_bigtable_gc_policy" "groupby_streaming_policy" {
  instance_name = google_bigtable_instance.zipline_bigtable_instance.name
  table = google_bigtable_table.groupby_streaming.name
  column_family = "cf"

  mode = "UNION"
  max_age {
    duration = "120h"
  }
  max_version {
    number = 10000
  }
}

resource "google_bigtable_table" "tile_summaries" {
  instance_name = google_bigtable_instance.zipline_bigtable_instance.name
  name = "TILE_SUMMARIES"
  column_family {
    family = "cf"
  }
}

resource "google_bigtable_gc_policy" "tile_summaries_gc_policy" {
  instance_name = google_bigtable_instance.zipline_bigtable_instance.name
  table = google_bigtable_table.tile_summaries.name
  column_family = "cf"

  mode = "UNION"
  max_age {
    duration = "120h"
  }
  max_version {
    number = 10000
  }
}

resource "google_bigtable_table" "chronon_metadata" {
  instance_name = google_bigtable_instance.zipline_bigtable_instance.name
  name = "CHRONON_METADATA"
  column_family {
    family = "cf"
  }
}

resource "google_bigtable_gc_policy" "chronon_metadata_gc_policy" {
  instance_name = google_bigtable_instance.zipline_bigtable_instance.name
  table = google_bigtable_table.chronon_metadata.name
  column_family = "cf"

  mode = "UNION"
  max_age {
    duration = "120h"
  }
  max_version {
    number = 10000
  }
}

resource "google_bigtable_table" "entity_keys_by_team" {
  instance_name = google_bigtable_instance.zipline_bigtable_instance.name
  name = "ENTITY_KEYS_BY_TEAM"
  column_family {
    family = "cf"
  }
}

resource "google_bigtable_gc_policy" "entity_keys_by_team_gc_policy" {
  instance_name = google_bigtable_instance.zipline_bigtable_instance.name
  table = google_bigtable_table.entity_keys_by_team.name
  column_family = "cf"

  mode = "UNION"
  max_age {
    duration = "120h"
  }
  max_version {
    number = 10000
  }
}
