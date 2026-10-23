locals {
  # Artifact bucket derived from orchestration.deployment.artifact_prefix (gs://name).
  artifact_bucket = split("/", trimsuffix(trimprefix(trimspace(local.deployment.artifact_prefix), "gs://"), "/"))[0]

  logs_bucket = local.cloud_args.logs_bucket != "" ? local.cloud_args.logs_bucket : "zipline-logs-${local.name_prefix}"

  # Attach-vs-create for spark_libs_bucket:
  #   - empty                        => create as zipline-spark-libs
  #   - name set, create knob unset  => attach existing (TF only grants) — AWS parity
  #   - name set, create knob true   => create under that name (use when global
  #                                     default zipline-spark-libs is taken)
  spark_libs_bucket_name = local.cloud_args.spark_libs_bucket != "" ? local.cloud_args.spark_libs_bucket : "zipline-spark-libs"
  create_spark_libs_bucket = local.cloud_args.spark_libs_bucket == "" || local.cloud_args.create_spark_libs_bucket

  # Buckets the four GSAs read/write. Separated out so identity.tf can
  # grant per-bucket IAM.
  owned_buckets = [
    local.cloud_args.warehouse_bucket,
    local.artifact_bucket,
    local.logs_bucket,
  ]
}

resource "google_storage_bucket" "warehouse" {
  name                        = local.cloud_args.warehouse_bucket
  location                    = local.cloud_args.region
  force_destroy               = local.cloud_args.bucket_force_destroy
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  dynamic "encryption" {
    for_each = local.cloud_args.cmek_key_id != "" ? [1] : []
    content {
      default_kms_key_name = local.cloud_args.cmek_key_id
    }
  }
}

resource "google_storage_bucket" "artifact" {
  name                        = local.artifact_bucket
  location                    = local.cloud_args.region
  force_destroy               = local.cloud_args.bucket_force_destroy
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  dynamic "encryption" {
    for_each = local.cloud_args.cmek_key_id != "" ? [1] : []
    content {
      default_kms_key_name = local.cloud_args.cmek_key_id
    }
  }
}

resource "google_storage_bucket" "logs" {
  name                        = local.logs_bucket
  location                    = local.cloud_args.region
  force_destroy               = local.cloud_args.bucket_force_destroy
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  dynamic "encryption" {
    for_each = local.cloud_args.cmek_key_id != "" ? [1] : []
    content {
      default_kms_key_name = local.cloud_args.cmek_key_id
    }
  }
}

resource "google_storage_bucket" "spark_libs" {
  count = local.create_spark_libs_bucket ? 1 : 0

  name                        = local.spark_libs_bucket_name
  location                    = local.cloud_args.region
  force_destroy               = local.cloud_args.bucket_force_destroy
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  dynamic "encryption" {
    for_each = local.cloud_args.cmek_key_id != "" ? [1] : []
    content {
      default_kms_key_name = local.cloud_args.cmek_key_id
    }
  }
}

# Materialize the Spark event-log prefix. GCS prefixes are not objects; without
# this zero-byte placeholder the Spark History Server exits FileNotFound before
# any Spark job has written events. Mirrors AWS's spark_events_prefix S3 object.
resource "google_storage_bucket_object" "spark_events_prefix" {
  name          = "spark-events/"
  bucket        = google_storage_bucket.warehouse.name
  content       = " "
  content_type  = "application/x-directory"
}

# Read-only reference to the shared warehouse bucket (zipline-warehouse-canary)
# so IAM bindings in identity.tf can target it. The bucket is managed outside
# this stack — bucket-level IAM accepts any principal, so a data source works
# whether it lives in canary-443022 or another project (R12 §16 open item 4).
data "google_storage_bucket" "shared_warehouse" {
  count = trimspace(tostring(local.cloud_args.shared_warehouse_bucket)) != "" ? 1 : 0
  name  = local.cloud_args.shared_warehouse_bucket
}
