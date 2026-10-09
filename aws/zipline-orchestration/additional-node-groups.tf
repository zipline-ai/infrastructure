# Keep the default group available while bringing up replacement capacity.
# Drain its nodes before reducing eks_min_size and eks_desired_size to zero.
resource "aws_eks_node_group" "additional" {
  for_each = try(var.aws.additional_node_groups, {})

  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.name_prefix}-${each.key}"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = [local.resolved_primary_subnet_id, local.resolved_secondary_subnet_id]
  instance_types  = [each.value.instance_type]
  version         = aws_eks_cluster.main.version

  launch_template {
    id      = aws_launch_template.eks_nodes.id
    version = aws_launch_template.eks_nodes.latest_version
  }

  scaling_config {
    desired_size = each.value.desired_size
    max_size     = each.value.max_size
    min_size     = each.value.min_size
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
    Name = "${local.name_prefix}-${each.key}-eks-node"
  }

  lifecycle {
    precondition {
      condition     = each.key != "default"
      error_message = "Additional node groups must use a name other than default."
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry,
    aws_kms_key.eks_node_root,
  ]
}
