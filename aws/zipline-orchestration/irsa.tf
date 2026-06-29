data "aws_iam_policy_document" "orchestration_irsa_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${local.orchestration_namespace}:${local.orchestration_service_account}"]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "orchestration_irsa" {
  name               = "${local.name_prefix}-orchestration-irsa"
  assume_role_policy = data.aws_iam_policy_document.orchestration_irsa_assume_role.json

  tags = {
    Name = "${local.name_prefix}-orchestration-irsa"
  }
}

data "aws_iam_policy_document" "orchestration_secrets_policy" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
    ]
    resources = compact(concat([
      aws_secretsmanager_secret.db_credentials.arn,
      local.auth_enabled ? local.auth_secret_arn : "",
    ], local.extra_secret_provider_arns))
  }
}

resource "aws_iam_role_policy" "orchestration_secrets" {
  name   = "${local.name_prefix}-orchestration-secrets"
  role   = aws_iam_role.orchestration_irsa.id
  policy = data.aws_iam_policy_document.orchestration_secrets_policy.json
}

data "aws_iam_policy_document" "orchestration_s3_policy" {
  statement {
    effect = "Allow"
    actions = [
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:PutObject",
    ]
    resources = [
      "arn:aws:s3:::${local.cloud_args.warehouse_bucket}",
      "arn:aws:s3:::${local.cloud_args.warehouse_bucket}/*",
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::${local.cloud_args.shared_warehouse_bucket}",
      "arn:aws:s3:::${local.cloud_args.shared_warehouse_bucket}/*",
    ]
  }

  dynamic "statement" {
    for_each = length(local.cloud_args.additional_data_buckets) > 0 ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "s3:GetObject",
        "s3:ListBucket",
      ]
      resources = flatten([
        for bucket in local.cloud_args.additional_data_buckets : [
          "arn:aws:s3:::${bucket}",
          "arn:aws:s3:::${bucket}/*",
        ]
      ])
    }
  }
}

resource "aws_iam_role_policy" "orchestration_s3" {
  name   = "${local.name_prefix}-orchestration-s3"
  role   = aws_iam_role.orchestration_irsa.id
  policy = data.aws_iam_policy_document.orchestration_s3_policy.json
}

resource "aws_iam_role_policy" "orchestration_polaris_storage_assume_role" {
  name = "${local.name_prefix}-polaris-storage-assume-role"
  role = aws_iam_role.orchestration_irsa.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = aws_iam_role.polaris_storage.arn
        Condition = {
          StringEquals = {
            "sts:ExternalId" = local.polaris_storage_external_id
          }
        }
      }
    ]
  })
}

data "aws_iam_policy_document" "orchestration_dynamodb_policy" {
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:BatchGetItem",
      "dynamodb:BatchWriteItem",
      "dynamodb:CreateTable",
      "dynamodb:DeleteItem",
      "dynamodb:DescribeTable",
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:UpdateItem",
      "dynamodb:UpdateTimeToLive",
    ]
    resources = [
      "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/*",
    ]
  }
}

resource "aws_iam_role_policy" "orchestration_dynamodb" {
  name   = "${local.name_prefix}-orchestration-dynamodb"
  role   = aws_iam_role.orchestration_irsa.id
  policy = data.aws_iam_policy_document.orchestration_dynamodb_policy.json
}

data "aws_iam_policy_document" "orchestration_cloudwatch_logs_policy" {
  statement {
    effect = "Allow"
    actions = [
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:FilterLogEvents",
      "logs:GetLogEvents",
      "logs:GetQueryResults",
      "logs:StartQuery",
      "logs:StopQuery",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "orchestration_cloudwatch_logs" {
  name   = "${local.name_prefix}-orchestration-cloudwatch-logs"
  role   = aws_iam_role.orchestration_irsa.id
  policy = data.aws_iam_policy_document.orchestration_cloudwatch_logs_policy.json
}

data "aws_iam_policy_document" "orchestration_amp_policy" {
  statement {
    effect = "Allow"
    actions = [
      "aps:GetLabels",
      "aps:GetMetricMetadata",
      "aps:GetSeries",
      "aps:QueryMetrics",
    ]
    resources = [local.amp_workspace_arn]
  }
}

resource "aws_iam_role_policy" "orchestration_amp" {
  name   = "${local.name_prefix}-orchestration-amp"
  role   = aws_iam_role.orchestration_irsa.id
  policy = data.aws_iam_policy_document.orchestration_amp_policy.json
}

data "aws_iam_policy_document" "orchestration_glue_policy" {
  statement {
    effect = "Allow"
    actions = [
      "glue:GetDatabase",
      "glue:GetDatabases",
      "glue:GetPartition",
      "glue:GetPartitions",
      "glue:GetTable",
      "glue:GetTables",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "orchestration_glue" {
  name   = "${local.name_prefix}-orchestration-glue"
  role   = aws_iam_role.orchestration_irsa.id
  policy = data.aws_iam_policy_document.orchestration_glue_policy.json
}

data "aws_iam_policy_document" "bedrock_invoke_policy" {
  statement {
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream",
    ]
    resources = [
      "arn:aws:bedrock:${data.aws_region.current.name}::foundation-model/*",
    ]
  }
}

resource "aws_iam_role_policy" "orchestration_bedrock" {
  name   = "${local.name_prefix}-orchestration-bedrock"
  role   = aws_iam_role.orchestration_irsa.id
  policy = data.aws_iam_policy_document.bedrock_invoke_policy.json
}

data "aws_iam_policy_document" "spark_compute_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]
    condition {
      test     = "StringLike"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values = [
        "system:serviceaccount:${local.compute_namespace_prefix}*:${local.spark_service_account}",
      ]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "spark_compute_execution" {
  name               = "${local.name_prefix}-spark-compute-execution"
  assume_role_policy = data.aws_iam_policy_document.spark_compute_assume_role.json
  description        = "IAM role for Spark compute jobs submitted through Crucible"

  tags = {
    Name = "${local.name_prefix}-spark-compute-execution"
  }
}

data "aws_iam_policy_document" "spark_compute_s3_policy" {
  statement {
    effect = "Allow"
    actions = [
      "s3:DeleteObject",
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:PutObject",
    ]
    resources = concat(
      [
        "arn:aws:s3:::${local.cloud_args.warehouse_bucket}",
        "arn:aws:s3:::${local.cloud_args.warehouse_bucket}/*",
        "arn:aws:s3:::${local.artifact_bucket}",
        "arn:aws:s3:::${local.artifact_bucket}/*",
        "arn:aws:s3:::${local.cloud_args.spark_libs_bucket}",
        "arn:aws:s3:::${local.cloud_args.spark_libs_bucket}/*",
        "arn:aws:s3:::${local.logs_bucket}",
        "arn:aws:s3:::${local.logs_bucket}/*",
      ],
      flatten([
        for bucket in local.cloud_args.additional_data_buckets : [
          "arn:aws:s3:::${bucket}",
          "arn:aws:s3:::${bucket}/*",
        ]
      ]),
    )
  }
}

resource "aws_iam_policy" "spark_compute_s3" {
  name        = "${local.name_prefix}-spark-compute-s3-policy"
  description = "S3 access policy for Spark compute jobs"
  policy      = data.aws_iam_policy_document.spark_compute_s3_policy.json
}

resource "aws_iam_role_policy_attachment" "spark_compute_s3" {
  role       = aws_iam_role.spark_compute_execution.name
  policy_arn = aws_iam_policy.spark_compute_s3.arn
}

data "aws_iam_policy_document" "spark_compute_dynamodb_policy" {
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:BatchGetItem",
      "dynamodb:BatchWriteItem",
      "dynamodb:CreateTable",
      "dynamodb:DeleteItem",
      "dynamodb:DescribeTable",
      "dynamodb:GetItem",
      "dynamodb:ImportTable",
      "dynamodb:PutItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:UpdateItem",
      "dynamodb:UpdateTable",
      "dynamodb:UpdateTimeToLive",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "spark_compute_dynamodb" {
  name   = "${local.name_prefix}-spark-compute-dynamodb"
  role   = aws_iam_role.spark_compute_execution.id
  policy = data.aws_iam_policy_document.spark_compute_dynamodb_policy.json
}

data "aws_iam_policy_document" "spark_compute_glue_policy" {
  statement {
    effect = "Allow"
    actions = [
      "glue:BatchCreatePartition",
      "glue:BatchDeletePartition",
      "glue:BatchGetPartition",
      "glue:BatchUpdatePartition",
      "glue:CreatePartition",
      "glue:CreateTable",
      "glue:DeletePartition",
      "glue:DeleteTable",
      "glue:GetDatabase",
      "glue:GetDatabases",
      "glue:GetPartition",
      "glue:GetPartitions",
      "glue:GetTable",
      "glue:GetTables",
      "glue:UpdatePartition",
      "glue:UpdateTable",
    ]
    resources = [
      "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:catalog",
      "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:database/*",
      "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/*/*",
    ]
  }
}

resource "aws_iam_role_policy" "spark_compute_glue" {
  name   = "${local.name_prefix}-spark-compute-glue"
  role   = aws_iam_role.spark_compute_execution.id
  policy = data.aws_iam_policy_document.spark_compute_glue_policy.json
}

data "aws_iam_policy_document" "flink_compute_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]
    condition {
      test     = "StringLike"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${local.compute_namespace_prefix}*:${local.flink_service_account}"]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flink_compute_execution" {
  name               = "${local.name_prefix}-flink-compute-execution"
  assume_role_policy = data.aws_iam_policy_document.flink_compute_assume_role.json
  description        = "IAM role for Flink compute jobs submitted through Crucible"

  tags = {
    Name = "${local.name_prefix}-flink-compute-execution"
  }
}

data "aws_iam_policy_document" "flink_compute_s3_policy" {
  statement {
    effect = "Allow"
    actions = [
      "s3:DeleteObject",
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:PutObject",
    ]
    resources = concat(
      [
        "arn:aws:s3:::${local.cloud_args.warehouse_bucket}",
        "arn:aws:s3:::${local.cloud_args.warehouse_bucket}/*",
        "arn:aws:s3:::${local.artifact_bucket}",
        "arn:aws:s3:::${local.artifact_bucket}/*",
        "arn:aws:s3:::${local.cloud_args.spark_libs_bucket}",
        "arn:aws:s3:::${local.cloud_args.spark_libs_bucket}/*",
        "arn:aws:s3:::${local.logs_bucket}",
        "arn:aws:s3:::${local.logs_bucket}/*",
      ],
      flatten([
        for bucket in local.cloud_args.additional_flink_s3_buckets : [
          "arn:aws:s3:::${bucket}",
          "arn:aws:s3:::${bucket}/*",
        ]
      ]),
    )
  }
}

resource "aws_iam_policy" "flink_compute_s3" {
  name        = "${local.name_prefix}-flink-compute-s3-policy"
  description = "S3 access policy for Flink compute jobs"
  policy      = data.aws_iam_policy_document.flink_compute_s3_policy.json
}

resource "aws_iam_role_policy_attachment" "flink_compute_s3" {
  role       = aws_iam_role.flink_compute_execution.name
  policy_arn = aws_iam_policy.flink_compute_s3.arn
}

data "aws_iam_policy_document" "flink_kinesis_policy" {
  statement {
    effect = "Allow"
    actions = [
      "kinesis:DescribeStream",
      "kinesis:DescribeStreamSummary",
      "kinesis:GetRecords",
      "kinesis:GetShardIterator",
      "kinesis:ListShards",
      "kinesis:ListStreams",
      "kinesis:SubscribeToShard",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "flink_compute_kinesis" {
  name   = "${local.name_prefix}-flink-compute-kinesis"
  role   = aws_iam_role.flink_compute_execution.id
  policy = data.aws_iam_policy_document.flink_kinesis_policy.json
}

data "aws_iam_policy_document" "flink_dynamodb_policy" {
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:BatchGetItem",
      "dynamodb:BatchWriteItem",
      "dynamodb:CreateTable",
      "dynamodb:CreateTableReplica",
      "dynamodb:DeleteItem",
      "dynamodb:DescribeTable",
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:UpdateItem",
      "dynamodb:UpdateTable",
      "dynamodb:UpdateTimeToLive",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "flink_compute_dynamodb" {
  name   = "${local.name_prefix}-flink-compute-dynamodb"
  role   = aws_iam_role.flink_compute_execution.id
  policy = data.aws_iam_policy_document.flink_dynamodb_policy.json
}

data "aws_iam_policy_document" "flink_glue_schema_registry_policy" {
  statement {
    effect = "Allow"
    actions = [
      "glue:GetRegistry",
      "glue:GetSchemaByDefinition",
      "glue:GetSchemaVersion",
      "glue:ListSchemaVersions",
    ]
    resources = [
      "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:registry/${local.glue_registry_name}",
      "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:schema/${local.glue_registry_name}/*",
    ]
  }
}

resource "aws_iam_role_policy" "flink_compute_glue_schema_registry" {
  name   = "${local.name_prefix}-flink-compute-glue-schema-registry"
  role   = aws_iam_role.flink_compute_execution.id
  policy = data.aws_iam_policy_document.flink_glue_schema_registry_policy.json
}

data "aws_iam_policy_document" "flink_compute_glue_catalog_policy" {
  statement {
    effect = "Allow"
    actions = [
      "glue:GetDatabase",
      "glue:GetDatabases",
      "glue:GetPartition",
      "glue:GetPartitions",
      "glue:GetTable",
      "glue:GetTables",
    ]
    resources = [
      "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:catalog",
      "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:database/*",
      "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/*/*",
    ]
  }
}

resource "aws_iam_role_policy" "flink_compute_glue_catalog" {
  name   = "${local.name_prefix}-flink-compute-glue-catalog"
  role   = aws_iam_role.flink_compute_execution.id
  policy = data.aws_iam_policy_document.flink_compute_glue_catalog_policy.json
}

data "aws_iam_policy_document" "flink_msk_policy" {
  count = local.cloud_args.msk_cluster_arn != "" ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "kafka-cluster:AlterCluster",
      "kafka-cluster:DescribeCluster",
      "kafka-cluster:DescribeClusterDynamicConfiguration",
      "kafka-cluster:Connect",
    ]
    resources = [local.cloud_args.msk_cluster_arn]
  }

  statement {
    effect = "Allow"
    actions = [
      "kafka-cluster:AlterTopic",
      "kafka-cluster:AlterTopicDynamicConfiguration",
      "kafka-cluster:CreateTopic",
      "kafka-cluster:DeleteTopic",
      "kafka-cluster:DescribeTopic",
      "kafka-cluster:DescribeTopicDynamicConfiguration",
    ]
    resources = ["${local.msk_topic_arn_prefix}/*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "kafka-cluster:AlterGroup",
      "kafka-cluster:DescribeGroup",
      "kafka-cluster:ReadData",
      "kafka-cluster:WriteData",
    ]
    resources = [
      "${local.msk_topic_arn_prefix}/*",
      "${local.msk_group_arn_prefix}/*",
    ]
  }
}

resource "aws_iam_role_policy" "flink_compute_msk" {
  count  = local.cloud_args.msk_cluster_arn != "" ? 1 : 0
  name   = "${local.name_prefix}-flink-compute-msk"
  role   = aws_iam_role.flink_compute_execution.id
  policy = data.aws_iam_policy_document.flink_msk_policy[0].json
}

data "aws_iam_policy_document" "polaris_storage_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.orchestration_irsa.arn]
    }
    actions = ["sts:AssumeRole"]
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [local.polaris_storage_external_id]
    }
  }
}

resource "aws_iam_role" "polaris_storage" {
  name               = "${local.name_prefix}-polaris-storage"
  assume_role_policy = data.aws_iam_policy_document.polaris_storage_assume_role.json
  description        = "Storage credential vending role for the Polaris catalog"

  tags = {
    Name = "${local.name_prefix}-polaris-storage"
  }
}

data "aws_iam_policy_document" "polaris_storage" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
    ]
    resources = [
      for bucket in local.polaris_storage_allowed_buckets : "arn:aws:s3:::${bucket}"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:ListMultipartUploadParts",
      "s3:PutObject",
    ]
    resources = [
      for bucket in local.polaris_storage_allowed_buckets : "arn:aws:s3:::${bucket}/*"
    ]
  }

  dynamic "statement" {
    for_each = length(local.polaris_storage_allowed_kms_keys) > 0 ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:Encrypt",
        "kms:GenerateDataKey*",
        "kms:ReEncrypt*",
      ]
      resources = local.polaris_storage_allowed_kms_keys
    }
  }
}

resource "aws_iam_role_policy" "polaris_storage" {
  name   = "${local.name_prefix}-polaris-storage"
  role   = aws_iam_role.polaris_storage.id
  policy = data.aws_iam_policy_document.polaris_storage.json
}
