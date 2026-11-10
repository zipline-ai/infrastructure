# Retained separately from EKS/RDS resets. Existing datasource buckets are not
# suitable evidence stores: no versioning and force_destroy=true in this module.
variable "training_artifact_bucket" {
  type        = string
  default     = ""
  description = "Opt-in retained training bucket; empty creates nothing. Never delete to reset a trial."
}
resource "aws_s3_bucket" "training" {
  count         = var.training_artifact_bucket != "" ? 1 : 0
  bucket        = var.training_artifact_bucket
  force_destroy = false
  lifecycle { prevent_destroy = true }
  tags = { Layer = "datasources", Purpose = "retained-training-evidence" }
}
resource "aws_s3_bucket_public_access_block" "training" {
  count                   = var.training_artifact_bucket != "" ? 1 : 0
  bucket                  = aws_s3_bucket.training[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_versioning" "training" {
  count  = var.training_artifact_bucket != "" ? 1 : 0
  bucket = aws_s3_bucket.training[0].id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "training" {
  count  = var.training_artifact_bucket != "" ? 1 : 0
  bucket = aws_s3_bucket.training[0].id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_lifecycle_configuration" "training" {
  count  = var.training_artifact_bucket != "" ? 1 : 0
  bucket = aws_s3_bucket.training[0].id
  rule {
    id     = "abort-incomplete-uploads-only"
    status = "Enabled"
    filter { prefix = "" }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
}
resource "aws_ecr_repository" "training" {
  count                = var.training_artifact_bucket != "" ? 1 : 0
  name                 = "${var.name_prefix}/s6e11-training"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false
  image_scanning_configuration { scan_on_push = true }
  lifecycle { prevent_destroy = true }
}
output "training_artifacts" {
  value = var.training_artifact_bucket == "" ? null : {
    bucket    = aws_s3_bucket.training[0].id
    registry  = aws_ecr_repository.training[0].repository_url
    retention = "Versioned; no object expiration or image lifecycle; prevent_destroy; no cross-region backup."
  }
}
