output "raw_bucket_name" {
  description = "S3 bucket containing raw public-demo datasource snapshots."
  value       = aws_s3_bucket.raw.id
}

output "curated_bucket_name" {
  description = "S3 bucket reserved for curated public-demo datasets."
  value       = aws_s3_bucket.curated.id
}

output "app_glue_database_name" {
  description = "Glue database for public-demo app, user activity, and server log tables."
  value       = aws_glue_catalog_database.app.name
}

output "ui_log_ingestor_function_name" {
  description = "Lambda function harvesting UI/server logs."
  value       = var.ui_logs_enabled ? aws_lambda_function.ui_log_ingestor[0].function_name : ""
}

output "ui_logs_freshness_profile" {
  description = "Active UI/server log harvesting freshness/cost profile."
  value       = var.ui_logs_freshness_profile
}

output "ui_logs_job_schedule" {
  description = "Configured UI/server log harvesting schedule."
  value       = var.ui_logs_enabled ? aws_cloudwatch_event_rule.ui_log_ingestor[0].schedule_expression : ""
}

output "ui_logs_source_location" {
  description = "Source handle for the public demo UI/server log configs."
  value = var.ui_logs_enabled ? {
    glue_table     = "${aws_glue_catalog_database.app.name}.${var.ui_logs_table_name}"
    curated_prefix = "s3://${aws_s3_bucket.curated.id}/${var.ui_logs_output_prefix}/"
    log_group_name = local.ui_logs_log_group_name
  } : null
}
