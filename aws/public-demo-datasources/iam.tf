data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }

}

resource "aws_iam_role" "lambda" {
  name               = "${local.lambda_role_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = {
    Environment = var.name_prefix
    Layer       = "datasources"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "lambda_datasource" {
  dynamic "statement" {
    for_each = var.ui_logs_enabled && var.ui_logs_streaming_enabled ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "kinesis:DescribeStreamSummary",
        "kinesis:PutRecord",
        "kinesis:PutRecords",
      ]
      resources = [aws_kinesis_stream.ui_access_events[0].arn]
    }
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = [
      "${aws_s3_bucket.raw.arn}/*",
      "${aws_s3_bucket.curated.arn}/*",
      "arn:aws:s3:::${var.warehouse_bucket}/*",
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.curated.arn,
      "arn:aws:s3:::${var.warehouse_bucket}",
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "glue:CreatePartition",
      "glue:CreateTable",
      "glue:DeleteTable",
      "glue:GetDatabase",
      "glue:GetPartition",
      "glue:GetPartitions",
      "glue:GetTable",
      "glue:GetTables",
      "glue:UpdatePartition",
      "glue:UpdateTable",
    ]
    resources = [
      aws_glue_catalog_database.app.arn,
      "arn:aws:glue:${var.aws_region}:*:catalog",
      "arn:aws:glue:${var.aws_region}:*:table/${aws_glue_catalog_database.app.name}/*",
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "athena:GetQueryExecution",
      "athena:GetQueryResults",
      "athena:GetWorkGroup",
      "athena:StartQueryExecution",
      "athena:StopQueryExecution",
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:FilterLogEvents",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "lambda_datasource" {
  name   = "${local.lambda_role_name}-datasource"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_datasource.json
}
