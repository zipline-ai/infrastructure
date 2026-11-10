data "aws_iam_policy_document" "gpu_training_trust" {
  count = var.gpu_training.enabled ? 1 : 0
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${local.gpu_namespace}:${local.spark_service_account}"]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "gpu_training" {
  count              = var.gpu_training.enabled ? 1 : 0
  name               = "${local.name_prefix}-s6e11-training"
  assume_role_policy = data.aws_iam_policy_document.gpu_training_trust[0].json
}
data "aws_iam_policy_document" "gpu_training_storage" {
  count = var.gpu_training.enabled ? 1 : 0
  statement {
    actions = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${var.gpu_training.data_bucket}/${var.gpu_training.data_prefix}*",
    "arn:aws:s3:::${var.gpu_training.retained_bucket}/${var.gpu_training.controller_prefix}*"]
  }
  statement {
    actions   = ["s3:PutObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"]
    resources = ["arn:aws:s3:::${var.gpu_training.retained_bucket}/${var.gpu_training.controller_prefix}runs/*"]
  }
  statement {
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.gpu_training.data_bucket}"]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${var.gpu_training.data_prefix}*"]
    }
  }
  statement {
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.gpu_training.retained_bucket}"]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${var.gpu_training.controller_prefix}*"]
    }
  }
  dynamic "statement" {
    for_each = length(var.gpu_training.kms_key_arns) > 0 ? [1] : []
    content {
      actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
      resources = var.gpu_training.kms_key_arns
      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["s3.${local.cloud_args.region}.amazonaws.com"]
      }
    }
  }
  dynamic "statement" {
    for_each = length(var.gpu_training.glue_resource_arns) > 0 ? [1] : []
    content {
      actions   = ["glue:GetDatabase", "glue:GetTable", "glue:GetPartitions", "glue:GetPartition", "glue:BatchGetPartition"]
      resources = var.gpu_training.glue_resource_arns
    }
  }
}
resource "aws_iam_role_policy" "gpu_training_storage" {
  count  = var.gpu_training.enabled ? 1 : 0
  role   = aws_iam_role.gpu_training[0].id
  policy = data.aws_iam_policy_document.gpu_training_storage[0].json
}
# The laptop assumes this role; it never uses the production Hub's IRSA identity.
resource "aws_iam_role" "gpu_submitter" {
  count = var.gpu_training.enabled ? 1 : 0
  name  = "${local.name_prefix}-s6e11-submitter"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Action = "sts:AssumeRole", Principal = { AWS = var.gpu_training.submitter_principal_arn }
  }] })
}
resource "aws_iam_role_policy" "gpu_submitter_storage" {
  count  = var.gpu_training.enabled ? 1 : 0
  role   = aws_iam_role.gpu_submitter[0].id
  policy = data.aws_iam_policy_document.gpu_training_storage[0].json
}
resource "aws_iam_role_policy" "gpu_submitter_cluster" {
  count = var.gpu_training.enabled ? 1 : 0
  role  = aws_iam_role.gpu_submitter[0].id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Action = ["eks:DescribeCluster"], Resource = aws_eks_cluster.main.arn
  }] })
}
resource "aws_eks_access_entry" "gpu_submitter" {
  count             = var.gpu_training.enabled ? 1 : 0
  cluster_name      = aws_eks_cluster.main.name
  principal_arn     = aws_iam_role.gpu_submitter[0].arn
  kubernetes_groups = ["zipline:s6e11-dev"]
  type              = "STANDARD"
}
resource "aws_iam_role_policy" "gpu_submitter_logs" {
  count = var.gpu_training.enabled ? 1 : 0
  role  = aws_iam_role.gpu_submitter[0].id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect   = "Allow", Action = ["logs:GetLogEvents", "logs:FilterLogEvents", "logs:DescribeLogStreams"],
    Resource = "arn:aws:logs:${local.cloud_args.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/eks/${local.cluster_name}/containers:*"
  }] })
}
