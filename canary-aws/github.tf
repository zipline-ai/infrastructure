data "aws_iam_role" "iam_github_actions_role" {
  name = "github_actions"
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
      "${module.base_setup.aws_s3_bucket_arn}",
      "${module.base_setup.aws_s3_bucket_arn}/*",
    ]
  }
  statement {
    effect = "Allow"
    actions = [
      "elasticmapreduce:AddJobFlowSteps",
      "elasticmapreduce:CancelSteps",
      "elasticmapreduce:Describe*",
      "glue:GetTable",
      "glue:DeleteTable",
      "s3:GetObjectTagging",
      "s3:PutObjectTagging",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_actions_access" {
  role   = data.aws_iam_role.iam_github_actions_role.name
  policy = data.aws_iam_policy_document.github_actions_access.json
}