resource "aws_iam_openid_connect_provider" "github-actions" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = []
}

data "aws_caller_identity" "internal" {}

resource "aws_iam_role" "github-actions" {
  name = "github_actions"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Federated" : "arn:aws:iam::${data.aws_caller_identity.internal.id}:oidc-provider/token.actions.githubusercontent.com"
        },
        "Action" : "sts:AssumeRoleWithWebIdentity",
        "Condition" : {
          "StringEquals" : {
            "token.actions.githubusercontent.com:aud" : "sts.amazonaws.com"
          },
          "StringLike" : {
            "token.actions.githubusercontent.com:sub" : "repo:zipline-ai/chronon:*"
          }
        }
      }
    ]
  })
}

data "aws_iam_policy_document" "github-actions" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
      "s3:DeleteObject",
    ]
    resources = [
      "${aws_s3_bucket.artifacts["canary"].arn}/*",
      "${aws_s3_bucket.artifacts["canary"].arn}",
    ]
  }
}

resource "aws_iam_role_policy" "github-actions" {
  name   = "github_actions"
  role   = aws_iam_role.github-actions.id
  policy = data.aws_iam_policy_document.github-actions.json
}