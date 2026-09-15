resource "aws_s3_bucket" "raw" {
  bucket        = var.raw_bucket
  force_destroy = true

  tags = {
    Name        = var.raw_bucket
    Environment = var.name_prefix
    Layer       = "datasources"
  }
}

resource "aws_s3_bucket" "curated" {
  bucket        = var.curated_bucket
  force_destroy = true

  tags = {
    Name        = var.curated_bucket
    Environment = var.name_prefix
    Layer       = "datasources"
  }
}

resource "aws_s3_bucket_public_access_block" "raw" {
  bucket = aws_s3_bucket.raw.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "curated" {
  bucket = aws_s3_bucket.curated.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
