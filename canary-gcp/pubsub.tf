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