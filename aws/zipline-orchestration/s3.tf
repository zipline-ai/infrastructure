resource "aws_s3_bucket" "artifact" {
  bucket        = local.artifact_bucket
  force_destroy = local.cloud_args.bucket_force_destroy

  tags = {
    Name = local.artifact_bucket
  }
}

resource "aws_s3_bucket" "warehouse" {
  bucket        = local.cloud_args.warehouse_bucket
  force_destroy = local.cloud_args.bucket_force_destroy

  tags = {
    Name = local.cloud_args.warehouse_bucket
  }
}

# Materialize the Spark event-log prefix so the Spark History Server can start on
# a fresh warehouse bucket. Without this object the default log dir
# (s3a://<warehouse>/spark-events) does not exist and the history server exits
# with FileNotFound before any Spark job has written events.
resource "aws_s3_object" "spark_events_prefix" {
  bucket       = aws_s3_bucket.warehouse.id
  key          = "spark-events/"
  content_type = "application/x-directory"
}

resource "aws_s3_bucket" "logs" {
  bucket        = local.logs_bucket
  force_destroy = local.cloud_args.bucket_force_destroy

  tags = {
    Name = local.logs_bucket
  }
}

resource "aws_s3_bucket_public_access_block" "artifact" {
  bucket = aws_s3_bucket.artifact.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "warehouse" {
  bucket = aws_s3_bucket.warehouse.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
