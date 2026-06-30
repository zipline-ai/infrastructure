locals {
  chronon_metadata_base_name = "CHRONON_METADATA"
  table_partitions_base_name = "TABLE_PARTITIONS"
  dynamodb_kms_key_arn       = local.cloud_args.encryption_kms_key_arn != "" ? local.cloud_args.encryption_kms_key_arn : null
}

resource "aws_dynamodb_table" "chronon_metadata" {
  name         = "${local.cloud_args.kv_table_prefix}${local.chronon_metadata_base_name}"
  billing_mode = "PAY_PER_REQUEST"

  attribute {
    name = "keyBytes"
    type = "B"
  }

  hash_key = "keyBytes"

  ttl {
    attribute_name = "ttl"
    enabled        = false
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = local.dynamodb_kms_key_arn
  }

  stream_enabled   = length(compact(local.cloud_args.kv_replica_regions)) > 0
  stream_view_type = length(compact(local.cloud_args.kv_replica_regions)) > 0 ? "NEW_AND_OLD_IMAGES" : null

  dynamic "replica" {
    for_each = toset(compact(local.cloud_args.kv_replica_regions))
    content {
      region_name = replica.value
      kms_key_arn = lookup(local.cloud_args.encryption_kms_key_arns, replica.value, local.dynamodb_kms_key_arn)
    }
  }
}

resource "aws_dynamodb_table" "table_partitions" {
  name           = "${local.cloud_args.kv_table_prefix}${local.table_partitions_base_name}"
  read_capacity  = local.cloud_args.kv_read_capacity
  write_capacity = local.cloud_args.kv_write_capacity

  attribute {
    name = "keyBytes"
    type = "B"
  }

  hash_key = "keyBytes"

  ttl {
    attribute_name = "ttl"
    enabled        = false
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = local.dynamodb_kms_key_arn
  }
}
