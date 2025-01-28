// Establishes an EKS cluster on AWS with 2 m6g.medium machines
resource "aws_eks_cluster" "zipline_eks" {
  name     = "Zipline-${var.customer_name}-EKS"
  role_arn = aws_iam_role.cluster_role.arn

  vpc_config {
    endpoint_private_access = true
    subnet_ids              = [aws_subnet.main.id, aws_subnet.secondary.id]
  }

  enabled_cluster_log_types = ["api", "audit"]

  tags = {
    "alpha.eksctl.io/cluster-oidc-enabled" = "true"
  }

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }
  bootstrap_self_managed_addons = false

  upgrade_policy {
    support_type = "STANDARD"
  }
}

resource "aws_eks_node_group" "arm_spot_node_group" {
  cluster_name    = aws_eks_cluster.zipline_eks.name
  node_group_name = "${var.customer_name}-arm-spot-node-group"
  node_role_arn   = aws_iam_role.ec2_role.arn
  subnet_ids      = [aws_subnet.main.id, aws_subnet.secondary.id]

  ami_type = "AL2_x86_64"

  instance_types = ["t3.large"]

  disk_size = 20

  scaling_config {
    desired_size = 2
    max_size     = 2
    min_size     = 2
  }

  update_config {
    max_unavailable = 1
  }

  capacity_type = "SPOT"

  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  # Otherwise, EKS will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
  depends_on = [
    aws_iam_role_policy_attachment.AmazonDynamoDBFullAccess,
    aws_iam_role_policy_attachment.AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.AmazonEC2ContainerRegistryReadOnly,
    aws_iam_role_policy_attachment.AmazonEMRFullAccessPolicy_v2,
  ]
}

# Addons

resource "aws_eks_addon" "cni" {
  cluster_name = aws_eks_cluster.zipline_eks.name
  addon_name   = "vpc-cni"
}


resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.zipline_eks.name
  addon_name   = "coredns"
  depends_on   = [aws_eks_node_group.arm_spot_node_group]
}


resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.zipline_eks.name
  addon_name   = "kube-proxy"
}

resource "aws_eks_addon" "agent_identity" {
  cluster_name = aws_eks_cluster.zipline_eks.name
  addon_name   = "eks-pod-identity-agent"
}


# Policies

data "aws_iam_policy_document" "eks_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "cluster_role" {
  name               = "zipline-${var.customer_name}-cluster-role"
  description        = "Allows the cluster Kubernetes control plane to manage AWS resources on your behalf."
  assume_role_policy = data.aws_iam_policy_document.eks_assume_role.json
}

resource "aws_iam_role_policy_attachment" "AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster_role.name
}

data "aws_iam_policy_document" "iam_eks_access_entry_policy" {
  statement {
    effect = "Allow"

    actions = [
      "eks:CreateAccessEntry",
      "eks:DescribeAccessEntry",
      "eks:DeleteAccessEntry",
      "eks:ListAssociatedAccessPolicies",
      "eks:AssociateAccessPolicy",
      "eks:DisassociateAccessPolicy"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "iam_eks_access_entry_policy" {
  name   = "iam_eks_access_entry_policy"
  role   = aws_iam_role.cluster_role.id
  policy = data.aws_iam_policy_document.iam_eks_access_entry_policy.json
}


data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "ec2_role" {
  name               = "zipline-${var.customer_name}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "AmazonDynamoDBFullAccess" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
  role       = aws_iam_role.ec2_role.name
}
resource "aws_iam_role_policy_attachment" "AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.ec2_role.name
}
resource "aws_iam_role_policy_attachment" "AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.ec2_role.name
}
resource "aws_iam_role_policy_attachment" "AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.ec2_role.name
}
resource "aws_iam_role_policy_attachment" "AmazonEMRFullAccessPolicy_v2" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEMRFullAccessPolicy_v2"
  role       = aws_iam_role.ec2_role.name
}

data "tls_certificate" "eks" {
  url = aws_eks_cluster.zipline_eks.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.zipline_eks.identity[0].oidc[0].issuer
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
  name               = "${var.customer_name}_s3_role"
  assume_role_policy = data.aws_iam_policy_document.s3_assume_role_policy.json
}

data "aws_iam_policy_document" "s3_role_policy" {
  statement {
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject"
    ]

    resources = [module.base_setup.aws_s3_bucket_arn]
  }
}

resource "aws_iam_policy" "s3_role_policy" {
  name   = "${var.customer_name}_s3_role_policy"
  policy = data.aws_iam_policy_document.s3_role_policy.json
}

resource "aws_iam_role_policy_attachment" "s3_role_policy_attachment" {
  role       = aws_iam_role.s3_role.name
  policy_arn = aws_iam_policy.s3_role_policy.arn
}

