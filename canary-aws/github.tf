data "aws_iam_role" "iam_github_actions_role" {
  name = "github_actions"
}

data "aws_s3_bucket" "zipline_warehouse_bucket" {
  bucket = "zipline-warehouse-${lower(var.customer_name)}"
}

data "aws_iam_policy_document" "github_actions_s3_access" {
  statement {
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [data.aws_iam_role.iam_github_actions_role.arn]
    }
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
      "s3:DeleteObject",
    ]
    resources = [
      "${data.aws_s3_bucket.zipline_warehouse_bucket.arn}",
      "${data.aws_s3_bucket.zipline_warehouse_bucket.arn}/*",
    ]
  }
  statement {
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [data.aws_iam_role.iam_github_actions_role.arn]
    }
    actions = [
      "glue:GetTable",
      "glue:DeleteTable",
    ]

  }
}

resource "aws_s3_bucket_policy" "github_actions_s3_access" {
  bucket = data.aws_s3_bucket.zipline_warehouse_bucket.id
  policy = data.aws_iam_policy_document.github_actions_s3_access.json
}