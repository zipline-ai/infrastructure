resource "aws_glue_catalog_database" "chronon_output" {
  name         = "public_demo_data"
  description  = "Public demo Chronon output tables"
  location_uri = "s3://${var.warehouse_bucket}/data/tables/public_demo_data.db"
}

resource "aws_glue_catalog_database" "app" {
  name        = var.ui_logs_glue_database_name
  description = "Public demo app, user activity, and server log datasource tables"
}

resource "aws_glue_catalog_table" "ui_access_logs" {
  count = var.ui_logs_enabled ? 1 : 0

  name          = var.ui_logs_table_name
  database_name = aws_glue_catalog_database.app.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    classification = "json"
    typeOfData     = "file"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.curated.id}/${var.ui_logs_output_prefix}/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "${var.ui_logs_table_name}-serde"
      serialization_library = "org.apache.hive.hcatalog.data.JsonSerDe"
    }

    columns {
      name = "event_id"
      type = "string"
    }

    columns {
      name = "ingestion_id"
      type = "string"
    }

    columns {
      name = "event_ts"
      type = "bigint"
    }

    columns {
      name = "event_time_iso"
      type = "string"
    }

    columns {
      name = "ingested_at"
      type = "string"
    }

    columns {
      name = "freshness_lag_seconds"
      type = "bigint"
    }

    columns {
      name = "log_stream"
      type = "string"
    }

    columns {
      name = "namespace"
      type = "string"
    }

    columns {
      name = "pod"
      type = "string"
    }

    columns {
      name = "container"
      type = "string"
    }

    columns {
      name = "client_ip"
      type = "string"
    }

    columns {
      name = "user_id"
      type = "string"
    }

    columns {
      name = "http_method"
      type = "string"
    }

    columns {
      name = "path"
      type = "string"
    }

    columns {
      name = "route_family"
      type = "string"
    }

    columns {
      name = "status_code"
      type = "int"
    }

    columns {
      name = "status_family"
      type = "string"
    }

    columns {
      name = "is_error"
      type = "int"
    }

    columns {
      name = "is_not_found"
      type = "int"
    }

    columns {
      name = "is_write"
      type = "int"
    }

    columns {
      name = "request_time_seconds"
      type = "double"
    }

    columns {
      name = "user_agent"
      type = "string"
    }

    columns {
      name = "raw_message"
      type = "string"
    }
  }

  partition_keys {
    name = "snapshot_date"
    type = "string"
  }
}
