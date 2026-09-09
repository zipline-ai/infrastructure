data "archive_file" "ui_log_ingestor" {
  count       = var.ui_logs_enabled ? 1 : 0
  type        = "zip"
  source_dir  = "${path.module}/lambda/ui_log_ingestor"
  output_path = "${path.module}/.terraform/ui_log_ingestor.zip"
  excludes    = ["__pycache__/*", "*.pyc"]
}

resource "aws_lambda_function" "ui_log_ingestor" {
  count = var.ui_logs_enabled ? 1 : 0

  function_name    = local.ui_logs_lambda_name
  description      = "Harvests Kubernetes UI access logs into S3 for the public demo"
  role             = aws_iam_role.lambda.arn
  handler          = "ingest.handler"
  runtime          = "python3.12"
  timeout          = 300
  memory_size      = 512
  layers           = [var.aws_sdk_pandas_layer_arn]
  filename         = data.archive_file.ui_log_ingestor[0].output_path
  source_code_hash = data.archive_file.ui_log_ingestor[0].output_base64sha256

  environment {
    variables = {
      CURATED_BUCKET               = aws_s3_bucket.curated.id
      GLUE_DATABASE                = aws_glue_catalog_database.app.name
      GLUE_TABLE                   = var.ui_logs_table_name
      LOG_GROUP_NAME               = local.ui_logs_log_group_name
      LOG_STREAM_PREFIXES          = join(",", var.ui_logs_log_stream_prefixes)
      LOOKBACK_MINUTES             = tostring(local.ui_logs_lookback_minutes)
      OUTPUT_PREFIX                = var.ui_logs_output_prefix
      ATHENA_WORKGROUP             = aws_athena_workgroup.ingestion.name
      USER_IDENTITY_GLUE_TABLE     = var.user_identity_table_name
      USER_IDENTITY_OUTPUT_PREFIX  = var.user_identity_output_prefix
      USER_IDENTITY_PARQUET_PREFIX = var.user_identity_parquet_output_prefix
      USER_IDENTITY_ICEBERG_TABLE  = var.user_identity_iceberg_table_name
      USER_IDENTITY_ICEBERG_PREFIX = var.user_identity_iceberg_output_prefix
      USER_IDENTITY_SNAPSHOT_DAYS  = tostring(var.user_identity_snapshot_days)
    }
  }

  tags = {
    Environment = var.name_prefix
    Layer       = "datasources"
  }
}

resource "aws_cloudwatch_event_rule" "ui_log_ingestor" {
  count = var.ui_logs_enabled ? 1 : 0

  name                = "${var.name_prefix}-ui-log-ingestor"
  description         = "Harvest recent Kubernetes/UI HTTP logs for the public demo"
  schedule_expression = local.ui_logs_schedule
}

resource "aws_cloudwatch_event_target" "ui_log_ingestor" {
  count = var.ui_logs_enabled ? 1 : 0

  rule      = aws_cloudwatch_event_rule.ui_log_ingestor[0].name
  target_id = "ui-log-ingestor"
  arn       = aws_lambda_function.ui_log_ingestor[0].arn

  input = jsonencode({
    identity_snapshot_days = var.user_identity_snapshot_days
    lookback_minutes       = local.ui_logs_lookback_minutes
  })
}

resource "aws_lambda_permission" "allow_ui_log_events" {
  count = var.ui_logs_enabled ? 1 : 0

  statement_id  = "AllowExecutionFromEventBridgeUiLogs"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ui_log_ingestor[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ui_log_ingestor[0].arn
}
