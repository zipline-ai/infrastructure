data "aws_iam_role" "iam_github_actions_role" {
  name = "github_actions"
}

data "aws_s3_bucket" "zipline_warehouse_bucket" {
  bucket = "zipline-warehouse-${lower(var.customer_name)}"
}

data "aws_iam_policy_document" "github_actions_access" {
  statement {
    effect = "Allow"
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
    actions = [
      "glue:GetTable",
      "glue:DeleteTable",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_actions_access" {
  role       = data.aws_iam_role.iam_github_actions_role.name
  policy = data.aws_iam_policy_document.github_actions_access.json
}