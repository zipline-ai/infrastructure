resource "aws_s3_bucket" "artifact" {
  bucket        = local.artifact_bucket
  force_destroy = true

  tags = {
    Name = local.artifact_bucket
  }
}

resource "aws_s3_bucket" "warehouse" {
  bucket        = local.cloud_args.warehouse_bucket
  force_destroy = true

  tags = {
    Name = local.cloud_args.warehouse_bucket
  }
}

resource "aws_s3_bucket" "logs" {
  bucket        = local.logs_bucket
  force_destroy = true

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
