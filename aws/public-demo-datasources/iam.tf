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
  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
    ]
    resources = [
      "${aws_s3_bucket.raw.arn}/*",
      "${aws_s3_bucket.curated.arn}/*",
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "glue:CreatePartition",
      "glue:GetPartition",
      "glue:UpdatePartition",
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
