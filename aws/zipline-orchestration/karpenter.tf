locals {
  karpenter_service_account_name = try(local.karpenter.service_account_name, "karpenter")
  karpenter_interruption_queue   = "${local.cluster_name}-karpenter-interruptions"
  karpenter_chart_values = {
    settings = {
      clusterName       = aws_eks_cluster.main.name
      eksControlPlane   = true
      interruptionQueue = try(aws_sqs_queue.karpenter_interruption[0].name, "")
      enableZonalShift  = local.karpenter.enable_zonal_shift
    }
    serviceAccount = {
      create = true
      name   = local.karpenter_service_account_name
      annotations = {
        "eks.amazonaws.com/role-arn" = try(aws_iam_role.karpenter_controller[0].arn, "")
      }
    }
    controller = {
      resources = {
        requests = {
          cpu    = "1"
          memory = "1Gi"
        }
        limits = {
          cpu    = "1"
          memory = "1Gi"
        }
      }
    }
  }
  karpenter_interruption_event_patterns = {
    health = {
      source        = ["aws.health"]
      "detail-type" = ["AWS Health Event"]
    }
    spot_interruption = {
      source        = ["aws.ec2"]
      "detail-type" = ["EC2 Spot Instance Interruption Warning"]
    }
    rebalance = {
      source        = ["aws.ec2"]
      "detail-type" = ["EC2 Instance Rebalance Recommendation"]
    }
    instance_state_change = {
      source        = ["aws.ec2"]
      "detail-type" = ["EC2 Instance State-change Notification"]
      detail = {
        state = ["stopping", "stopped", "shutting-down", "terminated"]
      }
    }
  }
}

resource "aws_iam_role" "karpenter_node" {
  count = local.karpenter.enabled ? 1 : 0

  name               = "${local.name_prefix}-karpenter-node-role"
  assume_role_policy = data.aws_iam_policy_document.eks_node_assume_role.json

  tags = {
    Name = "${local.name_prefix}-karpenter-node-role"
  }
}

resource "aws_iam_role_policy_attachment" "karpenter_node_worker" {
  count = local.karpenter.enabled ? 1 : 0

  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.karpenter_node[0].name
}

resource "aws_iam_role_policy_attachment" "karpenter_node_cni" {
  count = local.karpenter.enabled ? 1 : 0

  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.karpenter_node[0].name
}

resource "aws_iam_role_policy_attachment" "karpenter_node_registry" {
  count = local.karpenter.enabled ? 1 : 0

  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.karpenter_node[0].name
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ssm" {
  count = local.karpenter.enabled ? 1 : 0

  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.karpenter_node[0].name
}

resource "aws_iam_instance_profile" "karpenter_node" {
  count = local.karpenter.enabled ? 1 : 0

  name = "${local.name_prefix}-karpenter-node"
  role = aws_iam_role.karpenter_node[0].name
}

resource "aws_eks_access_entry" "karpenter_node" {
  count = local.karpenter.enabled ? 1 : 0

  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.karpenter_node[0].arn
  type          = "EC2_LINUX"
}

data "aws_iam_policy_document" "karpenter_controller_assume_role" {
  count = local.karpenter.enabled ? 1 : 0

  statement {
    effect = "Allow"
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${local.karpenter.namespace}:${local.karpenter_service_account_name}"]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "karpenter_controller" {
  count = local.karpenter.enabled ? 1 : 0

  name               = "${local.name_prefix}-karpenter-controller"
  assume_role_policy = data.aws_iam_policy_document.karpenter_controller_assume_role[0].json

  tags = {
    Name = "${local.name_prefix}-karpenter-controller"
  }
}

data "aws_iam_policy_document" "karpenter_controller" {
  count = local.karpenter.enabled ? 1 : 0

  statement {
    sid    = "AllowScopedEC2InstanceAccessActions"
    effect = "Allow"
    actions = [
      "ec2:RunInstances",
      "ec2:CreateFleet",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:ec2:${local.cloud_args.region}::image/*",
      "arn:${data.aws_partition.current.partition}:ec2:${local.cloud_args.region}::snapshot/*",
      "arn:${data.aws_partition.current.partition}:ec2:${local.cloud_args.region}:${data.aws_caller_identity.current.account_id}:security-group/*",
      "arn:${data.aws_partition.current.partition}:ec2:${local.cloud_args.region}:${data.aws_caller_identity.current.account_id}:subnet/*",
      "arn:${data.aws_partition.current.partition}:ec2:${local.cloud_args.region}:${data.aws_caller_identity.current.account_id}:capacity-reservation/*",
      "arn:${data.aws_partition.current.partition}:ec2:${local.cloud_args.region}:${data.aws_caller_identity.current.account_id}:placement-group/*",
    ]
  }

  statement {
    sid    = "AllowScopedEC2LaunchTemplateAccessActions"
    effect = "Allow"
    actions = [
      "ec2:RunInstances",
      "ec2:CreateFleet",
    ]
    resources = ["arn:${data.aws_partition.current.partition}:ec2:${local.cloud_args.region}:${data.aws_caller_identity.current.account_id}:launch-template/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${aws_eks_cluster.main.name}"
      values   = ["owned"]
    }
    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid    = "AllowScopedEC2InstanceActionsWithTags"
    effect = "Allow"
    actions = [
      "ec2:RunInstances",
      "ec2:CreateFleet",
      "ec2:CreateLaunchTemplate",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:ec2:${local.cloud_args.region}:${data.aws_caller_identity.current.account_id}:fleet/*",
      "arn:${data.aws_partition.current.partition}:ec2:${local.cloud_args.region}:${data.aws_caller_identity.current.account_id}:instance/*",
      "arn:${data.aws_partition.current.partition}:ec2:${local.cloud_args.region}:${data.aws_caller_identity.current.account_id}:volume/*",
      "arn:${data.aws_partition.current.partition}:ec2:${local.cloud_args.region}:${data.aws_caller_identity.current.account_id}:network-interface/*",
      "arn:${data.aws_partition.current.partition}:ec2:${local.cloud_args.region}:${data.aws_caller_identity.current.account_id}:launch-template/*",
      "arn:${data.aws_partition.current.partition}:ec2:${local.cloud_args.region}:${data.aws_caller_identity.current.account_id}:spot-instances-request/*",
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${aws_eks_cluster.main.name}"
      values   = ["owned"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/eks:eks-cluster-name"
      values   = [aws_eks_cluster.main.name]
    }
    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid       = "AllowScopedResourceCreationTagging"
    effect    = "Allow"
    actions   = ["ec2:CreateTags"]
    resources = ["arn:${data.aws_partition.current.partition}:ec2:${local.cloud_args.region}:${data.aws_caller_identity.current.account_id}:*/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${aws_eks_cluster.main.name}"
      values   = ["owned"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/eks:eks-cluster-name"
      values   = [aws_eks_cluster.main.name]
    }
    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["RunInstances", "CreateFleet", "CreateLaunchTemplate"]
    }
    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid    = "AllowScopedResourceMutation"
    effect = "Allow"
    actions = [
      "ec2:CreateTags",
      "ec2:DeleteTags",
      "ec2:TerminateInstances",
      "ec2:DeleteLaunchTemplate",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:ec2:${local.cloud_args.region}:${data.aws_caller_identity.current.account_id}:instance/*",
      "arn:${data.aws_partition.current.partition}:ec2:${local.cloud_args.region}:${data.aws_caller_identity.current.account_id}:launch-template/*",
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${aws_eks_cluster.main.name}"
      values   = ["owned"]
    }
    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid    = "AllowRegionalReadActions"
    effect = "Allow"
    actions = [
      "ec2:Describe*",
      "ssm:GetParameter",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "AllowPricingReadActions"
    effect    = "Allow"
    actions   = ["pricing:GetProducts"]
    resources = ["*"]
  }

  statement {
    sid       = "AllowEKSServerEndpointDiscovery"
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = [aws_eks_cluster.main.arn]
  }

  statement {
    sid       = "AllowPassingInstanceRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.karpenter_node[0].arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com", "ec2.amazonaws.com.cn"]
    }
  }

  statement {
    sid    = "AllowInstanceProfileRead"
    effect = "Allow"
    actions = [
      "iam:GetInstanceProfile",
      "iam:ListInstanceProfiles",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowInterruptionQueueActions"
    effect = "Allow"
    actions = [
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:ReceiveMessage",
    ]
    resources = [aws_sqs_queue.karpenter_interruption[0].arn]
  }

  dynamic "statement" {
    for_each = local.karpenter.enable_zonal_shift ? [1] : []
    content {
      sid       = "AllowZonalShiftStatusReadOnly"
      effect    = "Allow"
      actions   = ["arc-zonal-shift:GetManagedResource"]
      resources = ["*"]
      condition {
        test     = "StringEquals"
        variable = "arc-zonal-shift:ResourceIdentifier"
        values   = [aws_eks_cluster.main.arn]
      }
    }
  }
}

resource "aws_iam_role_policy" "karpenter_controller" {
  count = local.karpenter.enabled ? 1 : 0

  name   = "${local.name_prefix}-karpenter-controller"
  role   = aws_iam_role.karpenter_controller[0].id
  policy = data.aws_iam_policy_document.karpenter_controller[0].json
}

resource "aws_sqs_queue" "karpenter_interruption" {
  count = local.karpenter.enabled ? 1 : 0

  name                      = local.karpenter_interruption_queue
  message_retention_seconds = 300
}

data "aws_iam_policy_document" "karpenter_interruption_queue" {
  count = local.karpenter.enabled ? 1 : 0

  statement {
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.karpenter_interruption[0].arn]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_sqs_queue_policy" "karpenter_interruption" {
  count = local.karpenter.enabled ? 1 : 0

  queue_url = aws_sqs_queue.karpenter_interruption[0].id
  policy    = data.aws_iam_policy_document.karpenter_interruption_queue[0].json
}

resource "aws_cloudwatch_event_rule" "karpenter_interruption" {
  for_each = {
    for key, pattern in local.karpenter_interruption_event_patterns : key => pattern
    if local.karpenter.enabled
  }

  name          = "${local.cluster_name}-karpenter-${replace(each.key, "_", "-")}"
  event_pattern = jsonencode(each.value)
}

resource "aws_cloudwatch_event_target" "karpenter_interruption" {
  for_each = {
    for key, pattern in local.karpenter_interruption_event_patterns : key => pattern
    if local.karpenter.enabled
  }

  rule      = aws_cloudwatch_event_rule.karpenter_interruption[each.key].name
  target_id = "karpenter-interruption-queue"
  arn       = aws_sqs_queue.karpenter_interruption[0].arn
}

resource "helm_release" "karpenter" {
  count = local.karpenter.enabled ? 1 : 0

  name             = local.karpenter.release_name
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = local.karpenter.version
  namespace        = local.karpenter.namespace
  create_namespace = true
  wait             = true

  values = [
    yamlencode(local.karpenter_chart_values),
    yamlencode(local.karpenter.values),
  ]

  depends_on = [
    aws_eks_node_group.default,
    aws_iam_role_policy.karpenter_controller,
    aws_sqs_queue_policy.karpenter_interruption,
  ]
}

resource "helm_release" "karpenter_nodepools" {
  count = local.karpenter.enabled ? 1 : 0

  name      = "${local.karpenter.release_name}-nodepools"
  chart     = "${path.module}/charts/karpenter-nodepools"
  namespace = local.karpenter.namespace
  wait      = true

  values = [
    yamlencode({
      ec2NodeClass = local.karpenter_ec2_node_class
      nodePools    = local.karpenter_node_pools
    })
  ]

  depends_on = [
    helm_release.karpenter,
  ]
}
