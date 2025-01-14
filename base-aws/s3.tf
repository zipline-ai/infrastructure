resource "aws_s3_bucket" "zipline_canary_bucket" {
  bucket = "${lower(var.name)}-data-bucket"
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.zipline_canary_eks.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
}

resource "kubernetes_service_account" "s3_service_account" {
  metadata {
    name      = "s3-sa"
    namespace = "default"
  }
}

data "aws_iam_policy_document" "s3_assume_role_policy" {
  statement {
    effect = "Allow"
    principals {
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
      type        = "Federated"
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]
    condition {
      test     = "StringEquals"
      variable = "${aws_iam_openid_connect_provider.eks.url}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "${aws_iam_openid_connect_provider.eks.url}:sub"
      values   = ["system:serviceaccount:default:${kubernetes_service_account.s3_service_account.metadata[0].name}"]
    }
  }
}

resource "aws_iam_role" "s3_role" {
  name               = "${var.name}_s3_role"
  assume_role_policy = data.aws_iam_policy_document.s3_assume_role_policy.json
}

data "aws_iam_policy_document" "s3_role_policy" {
  statement {
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject"
    ]

    resources = [aws_s3_bucket.zipline_canary_bucket.arn]
  }
}

resource "aws_iam_policy" "s3_role_policy" {
  name   = "${var.name}_s3_role_policy"
  policy = data.aws_iam_policy_document.s3_role_policy.json
}

resource "aws_iam_role_policy_attachment" "s3_role_policy_attachment" {
  role       = aws_iam_role.s3_role.name
  policy_arn = aws_iam_policy.s3_role_policy.arn
}

