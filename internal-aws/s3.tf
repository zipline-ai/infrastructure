resource "aws_s3_bucket" "artifacts" {
  for_each = var.customer_accounts
  bucket   = "zipline-artifacts-${lower(each.key)}"
}

data "aws_iam_policy_document" "allow_access_from_emr_and_github" {
  for_each = var.customer_accounts
  statement {
    effect = "Allow"
    principals {
      type = "AWS"
      identifiers = [ "${each.value}" ]
    }
    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]

    resources = [
      "${aws_s3_bucket.artifacts[each.key].arn}",
      "${aws_s3_bucket.artifacts[each.key].arn}/*",
    ]
  }
  statement {
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.github-actions.arn]
    }
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
      "s3:DeleteObject",
    ]
    resources = [
      "${aws_s3_bucket.artifacts[each.key].arn}/*",
      "${aws_s3_bucket.artifacts[each.key].arn}",
    ]
  }
  depends_on = [
    aws_s3_bucket.artifacts
  ]
}

resource "aws_s3_bucket_policy" "allow_access_from_emr_and_github" {
  for_each = var.customer_accounts
  bucket   = aws_s3_bucket.artifacts[each.key].id
  policy   = data.aws_iam_policy_document.allow_access_from_emr_and_github[each.key].json
}

resource "aws_s3_bucket" "dev_artifacts" {
  bucket = "zipline-artifacts-dev"
}

resource "aws_s3_bucket" "base_artifacts" {
  bucket = "zipline-artifacts-base"
}

data "aws_iam_policy_document" "dev_allow_access_from_emr_and_github" {
  statement {
    effect = "Allow"

    actions = [
      "s3:GetObject"
    ]

    resources = [
      "${aws_s3_bucket.dev_artifacts.arn}/*",
    ]
    principals {
      type = "AWS"
      identifiers = [
        "arn:aws:iam::345594603419:role/zipline_canary_emr_profile_role",
      ]
    }
  }
  statement {
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.github-actions.arn]
    }
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
      "s3:DeleteObject",
    ]
    resources = [
      "${aws_s3_bucket.dev_artifacts.arn}/*",
      "${aws_s3_bucket.dev_artifacts.arn}",
    ]
  }
  depends_on = [
    aws_s3_bucket.artifacts
  ]
}

resource "aws_s3_bucket_policy" "dev_allow_access_from_emr_and_github" {
  bucket = aws_s3_bucket.dev_artifacts.id
  policy = data.aws_iam_policy_document.dev_allow_access_from_emr_and_github.json
}

data "aws_iam_policy_document" "base_allow_access_from_emr_and_github" {
  statement {
    effect = "Allow"

    actions = [
      "s3:GetObject"
    ]

    resources = [
      "${aws_s3_bucket.base_artifacts.arn}/*",
    ]
    principals {
      type = "AWS"
      identifiers = [
        "arn:aws:iam::345594603419:role/zipline_canary_emr_profile_role",
      ]
    }
  }
  statement {
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.github-actions.arn]
    }
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
      "s3:DeleteObject",
    ]
    resources = [
      "${aws_s3_bucket.base_artifacts.arn}/*",
      "${aws_s3_bucket.base_artifacts.arn}",
    ]
  }
  depends_on = [
    aws_s3_bucket.artifacts
  ]
}

resource "aws_s3_bucket_policy" "base_allow_access_from_emr_and_github" {
  bucket = aws_s3_bucket.base_artifacts.id
  policy = data.aws_iam_policy_document.base_allow_access_from_emr_and_github.json
}