data "aws_iam_policy_document" "eks_cluster_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "eks_cluster_role" {
  name               = "${local.name_prefix}-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_assume_role.json

  tags = {
    Name = "${local.name_prefix}-eks-cluster-role"
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_security_group" "zipline" {
  name        = "zipline-${local.name_prefix}-sg"
  description = "Security group for Zipline"
  vpc_id      = local.cloud_args.vpc_id

  tags = {
    Name = "zipline-${local.name_prefix}-sg"
  }
}

resource "aws_vpc_security_group_egress_rule" "zipline_allow_all" {
  security_group_id = aws_security_group.zipline.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_security_group" "eks_cluster" {
  name        = "${local.name_prefix}-eks-cluster-sg"
  description = "Security group for EKS cluster"
  vpc_id      = local.cloud_args.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-eks-cluster-sg"
  }
}

resource "aws_security_group_rule" "eks_cluster_ingress_https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.eks_cluster.id
  description       = "Allow HTTPS access to the EKS API server"
}

resource "aws_eks_cluster" "main" {
  name     = local.cluster_name
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = local.cloud_args.eks_version

  vpc_config {
    subnet_ids              = [local.cloud_args.primary_subnet_id, local.cloud_args.secondary_subnet_id]
    endpoint_private_access = true
    endpoint_public_access  = true
    security_group_ids      = [aws_security_group.eks_cluster.id]
  }

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags = {
    Name = local.cluster_name
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource_controller,
  ]
}

resource "aws_security_group_rule" "eks_to_rds" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  security_group_id        = aws_security_group.zipline.id
  description              = "Allow EKS nodes to access RDS PostgreSQL"
}

resource "aws_eks_access_entry" "personnel" {
  for_each = toset(local.cloud_args.personnel_arns)

  cluster_name  = aws_eks_cluster.main.name
  principal_arn = each.value
}

resource "aws_eks_access_policy_association" "personnel_cluster_admin" {
  for_each = toset(local.cloud_args.personnel_arns)

  cluster_name  = aws_eks_cluster.main.name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.personnel]
}

data "aws_iam_policy_document" "eks_node_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "eks_node_role" {
  name               = "${local.name_prefix}-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.eks_node_assume_role.json

  tags = {
    Name = "${local.name_prefix}-eks-node-role"
  }
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_container_registry" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_role.name
}

data "aws_iam_policy_document" "eks_node_root_key_policy" {
  statement {
    sid    = "EnableIAMUserPermissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowEKSServiceGrantsForEBS"
    effect = "Allow"
    principals {
      type = "AWS"
      # Karpenter launches nodes directly (no ASG) with the CMK-encrypted root
      # volume. Both the controller (RunInstances caller) and the node/instance
      # role must be able to create the EBS-encryption grant; without CreateGrant
      # on the node role, EC2 terminates the instance at launch with
      # Client.InvalidKMSKey.InvalidState and it never joins.
      identifiers = concat(
        [aws_iam_role.eks_cluster_role.arn],
        local.karpenter.enabled ? [
          aws_iam_role.karpenter_controller[0].arn,
          aws_iam_role.karpenter_node[0].arn,
        ] : [],
      )
    }
    actions   = ["kms:CreateGrant"]
    resources = ["*"]
    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }

  statement {
    sid    = "AllowAutoScalingServiceLinkedRole"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"]
    }
    actions = [
      "kms:CreateGrant",
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey*",
      "kms:ReEncrypt*",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowNodeAndKarpenterKeyUsage"
    effect = "Allow"
    principals {
      type = "AWS"
      # The node/instance roles read their encrypted volume at boot. The
      # Karpenter controller ALSO needs the key-usage ops (not just CreateGrant):
      # it calls RunInstances directly, so it must GenerateDataKey/Decrypt to
      # create the encrypted volume at launch — the managed node group gets this
      # via the ASG service-linked role, which Karpenter has no equivalent of.
      identifiers = concat(
        [aws_iam_role.eks_node_role.arn],
        local.karpenter.enabled ? [
          aws_iam_role.karpenter_node[0].arn,
          aws_iam_role.karpenter_controller[0].arn,
        ] : [],
      )
    }
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey*",
      "kms:ReEncrypt*",
    ]
    resources = ["*"]
  }
}

resource "aws_kms_key" "eks_node_root" {
  description             = "KMS key for Zipline EKS node root volume encryption"
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.eks_node_root_key_policy.json

  tags = {
    Name = "${local.name_prefix}-eks-node-root-key"
  }
}

resource "aws_launch_template" "eks_nodes" {
  name_prefix = "${local.name_prefix}-eks-nodes"
  description = "Launch template for Zipline EKS nodes"

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size = local.cloud_args.eks_disk_size
      volume_type = "gp3"
      encrypted   = true
      kms_key_id  = aws_kms_key.eks_node_root.arn
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name = "${local.name_prefix}-eks-node-root-volume"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.name_prefix}-default"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = [local.cloud_args.primary_subnet_id, local.cloud_args.secondary_subnet_id]
  instance_types  = [local.cloud_args.eks_instance_type]
  version         = aws_eks_cluster.main.version

  launch_template {
    id      = aws_launch_template.eks_nodes.id
    version = aws_launch_template.eks_nodes.latest_version
  }

  scaling_config {
    desired_size = local.cloud_args.eks_desired_size
    max_size     = local.cloud_args.eks_max_size
    min_size     = local.cloud_args.eks_min_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    role                   = "zipline-workload"
    "zipline.ai/team"      = "default"
    "zipline.ai/node-pool" = "default"
  }

  tags = {
    Name = "${local.name_prefix}-eks-node"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry,
    aws_kms_key.eks_node_root,
  ]
}

data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = {
    Name = "${local.name_prefix}-eks-oidc"
  }
}
