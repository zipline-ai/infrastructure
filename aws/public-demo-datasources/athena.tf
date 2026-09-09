resource "aws_athena_workgroup" "ingestion" {
  name        = "${var.name_prefix}-datasource-ingestion"
  description = "Bounded Athena workgroup for public demo Iceberg ingestion"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.curated.id}/tmp/athena-results/"
    }
  }

  tags = {
    Environment = var.name_prefix
    Layer       = "datasources"
  }
}
