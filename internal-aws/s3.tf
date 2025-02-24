resource "aws_s3_bucket" "artifacts" {
  for_each = var.customer_projects
  bucket   = "zipline-artifacts-${lower(each.key)}"
}

data "aws_iam_policy_document" "allow_access_from_emr" {
  for_each = var.customer_projects
  statement {
    effect = "Allow"

    actions = [
      "s3:GetObject"
    ]

    resources = [
      aws_s3_bucket.artifacts[each.key].arn,
    ]
    principals {
      type = "AWS"
      identifiers = [
        "arn:aws:iam::${each.value}:role/zipline-${each.key}-ec2-role",
      ]
    }
  }
}

resource "aws_s3_bucket_policy" "allow_access_from_emr" {
  for_each = var.customer_projects
  bucket   = aws_s3_bucket.artifacts[each.key].id
  policy   = data.aws_iam_policy_document.allow_access_from_emr[each.key].json
}