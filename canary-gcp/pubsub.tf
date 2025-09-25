################################################################
# Pub/Sub Schema and Topic Management

# Schema for LoggableResponse
resource "google_pubsub_schema" "loggable_response_schema" {
  name    = "loggable-response-schema"
  type    = "AVRO"
  project = data.google_project.zipline.project_id

  definition = jsonencode({
    type = "record"
    name = "loggableResponse"
    namespace = "ai.chronon.data"
    doc = ""
    fields = [
      {
        name = "keyBytes"
        type = ["null", "bytes"]
        doc = ""
      },
      {
        name = "valueBytes"
        type = ["null", "bytes"]
        doc = ""
      },
      {
        name = "joinName"
        type = ["null", "string"]
        doc = ""
      },
      {
        name = "tsMillis"
        type = ["null", "long"]
        doc = ""
      },
      {
        name = "schemaHash"
        type = ["null", "string"]
        doc = ""
      }
    ]
  })
}

# Pub/Sub topic with schema validation
resource "google_pubsub_topic" "canary_logging_ooc" {
  name    = "canary-logging-ooc"
  project = data.google_project.zipline.project_id

  schema_settings {
    schema   = google_pubsub_schema.loggable_response_schema.id
    encoding = "BINARY"
  }
}

################################################################
# BigQuery Dataset and Table for Logging

resource "google_bigquery_dataset" "data" {
  dataset_id  = "data"
  description = "Dataset for storing Chronon out-of-core responses"
  location    = var.region
  project     = data.google_project.zipline.project_id

  delete_contents_on_destroy = false
}

resource "google_bigquery_table" "loggable_response" {
  dataset_id = google_bigquery_dataset.data.dataset_id
  table_id   = "loggable_response"
  project    = data.google_project.zipline.project_id

  schema = jsonencode([
    {
      name = "keyBytes"
      type = "BYTES"
      mode = "NULLABLE"
    },
    {
      name = "valueBytes"
      type = "BYTES"
      mode = "NULLABLE"
    },
    {
      name = "joinName"
      type = "STRING"
      mode = "NULLABLE"
    },
    {
      name = "tsMillis"
      type = "INTEGER"
      mode = "NULLABLE"
    },
    {
      name = "schemaHash"
      type = "STRING"
      mode = "NULLABLE"
    }
  ])

  deletion_protection = false
}

################################################################
# Pub/Sub Subscription for BigQuery Writing

resource "google_pubsub_subscription" "canary_logging_bigquery" {
  name    = "canary-logging-bigquery-sub"
  topic   = google_pubsub_topic.canary_logging_ooc.name
  project = data.google_project.zipline.project_id

  ack_deadline_seconds       = 10
  message_retention_duration = "604800s" # 7 days

  bigquery_config {
    table = "${data.google_project.zipline.project_id}.${google_bigquery_dataset.data.dataset_id}.${google_bigquery_table.loggable_response.table_id}"
    use_topic_schema = true
    drop_unknown_fields = false
    write_metadata = false
  }

  expiration_policy {
    ttl = "2678400s" # 31 days
  }

  retry_policy {
    minimum_backoff = "0s"
  }
}