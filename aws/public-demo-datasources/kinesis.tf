data "aws_caller_identity" "current" {}

resource "aws_kinesis_stream" "ui_access_events" {
  count = var.ui_logs_enabled && var.ui_logs_streaming_enabled ? 1 : 0

  name             = var.ui_logs_stream_name
  shard_count      = var.ui_logs_stream_shard_count
  retention_period = 24

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }

  tags = {
    Environment = var.name_prefix
    Layer       = "datasources"
  }
}

resource "aws_glue_registry" "streaming" {
  count = var.ui_logs_enabled && var.ui_logs_streaming_enabled ? 1 : 0

  registry_name = var.glue_schema_registry_name
  description   = "Persistent schemas for public-demo streaming sources"
}

resource "aws_glue_schema" "ui_access_events" {
  count = var.ui_logs_enabled && var.ui_logs_streaming_enabled ? 1 : 0

  schema_name   = var.ui_logs_stream_schema_name
  registry_arn  = aws_glue_registry.streaming[0].arn
  data_format   = "JSON"
  compatibility = "BACKWARD"
  schema_definition = jsonencode({
    title = "ui_access_event"
    type  = "object"
    properties = {
      event_id              = { type = "string" }
      ingestion_id          = { type = "string" }
      event_ts              = { type = "integer" }
      event_time_iso        = { type = "string" }
      ingested_at           = { type = "string" }
      freshness_lag_seconds = { type = "integer" }
      log_stream            = { type = "string" }
      namespace             = { type = "string" }
      pod                   = { type = "string" }
      container             = { type = "string" }
      client_ip             = { type = "string" }
      user_id               = { type = "string" }
      http_method           = { type = "string" }
      path                  = { type = "string" }
      route_family          = { type = "string" }
      status_code           = { type = "integer" }
      status_family         = { type = "string" }
      is_error              = { type = "integer" }
      is_not_found          = { type = "integer" }
      is_write              = { type = "integer" }
      request_time_seconds  = { type = "number" }
      user_agent            = { type = "string" }
      raw_message           = { type = "string" }
    }
  })
}
