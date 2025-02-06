resource "aws_emr_cluster" "emr_cluster" {
  name          = "zipline-${var.customer_name}-emr"
  release_label = "emr-7.2.0"
  applications  = ["Spark", "Flink", "Hadoop", "Hive", "JupyterEnterpriseGateway", "Livy", "Zeppelin"]

  configurations = jsonencode([
    {
      classification = "spark-hive-site"
      properties = {
        "hive.metastore.client.factory.class" = "com.amazonaws.glue.catalog.metastore.AWSGlueDataCatalogHiveClientFactory"
      }
    }
  ])

  ec2_attributes {
    subnet_id                         = var.emr_subnetwork != "" ? var.emr_subnetwork : aws_subnet.main.id
    instance_profile                  = aws_iam_instance_profile.emr_profile.arn
    emr_managed_master_security_group = aws_security_group.emr_sg.id
    emr_managed_slave_security_group  = aws_security_group.emr_sg.id
  }
  dynamic "bootstrap_action" {
    for_each = var.emr_bootstrap_actions
    content {
      path = bootstrap_action.value
      name = bootstrap_action.key
    }
  }
  tags = var.emr_tags
  master_instance_group {
    instance_type = "m5.xlarge"
  }
  core_instance_group {
    instance_type = "m5.xlarge"
  }
  service_role = aws_iam_role.iam_emr_service_role.arn
}

resource "aws_emr_managed_scaling_policy" "zipline_scaling" {
  cluster_id = aws_emr_cluster.emr_cluster.id
  compute_limits {
    maximum_capacity_units = 256
    minimum_capacity_units = 1
    unit_type              = "Instances"
  }
}

###
# IAM Role setups
###
# IAM role for EMR Service
data "aws_iam_policy_document" "emr_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["elasticmapreduce.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}
resource "aws_iam_role" "iam_emr_service_role" {
  name               = "zipline_${var.customer_name}_emr_service_role"
  assume_role_policy = data.aws_iam_policy_document.emr_assume_role.json
}
data "aws_iam_policy_document" "iam_emr_service_policy" {
  statement {
    effect = "Allow"
    actions = [
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:CancelSpotInstanceRequests",
      "ec2:CreateNetworkInterface",
      "ec2:CreateSecurityGroup",
      "ec2:CreateTags",
      "ec2:DeleteNetworkInterface",
      "ec2:DeleteSecurityGroup",
      "ec2:DeleteTags",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeAccountAttributes",
      "ec2:DescribeDhcpOptions",
      "ec2:DescribeInstanceStatus",
      "ec2:DescribeInstances",
      "ec2:DescribeKeyPairs",
      "ec2:DescribeNetworkAcls",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribePrefixLists",
      "ec2:DescribeRouteTables",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSpotInstanceRequests",
      "ec2:DescribeSpotPriceHistory",
      "ec2:DescribeSubnets",
      "ec2:DescribeVpcAttribute",
      "ec2:DescribeVpcEndpoints",
      "ec2:DescribeVpcEndpointServices",
      "ec2:DescribeVpcs",
      "ec2:DetachNetworkInterface",
      "ec2:ModifyImageAttribute",
      "ec2:ModifyInstanceAttribute",
      "ec2:RequestSpotInstances",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:RunInstances",
      "ec2:TerminateInstances",
      "ec2:DeleteVolume",
      "ec2:DescribeVolumeStatus",
      "ec2:DescribeVolumes",
      "ec2:DetachVolume",
      "glue:*",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListInstanceProfiles",
      "iam:ListRolePolicies",
      "iam:PassRole",
      "s3:CreateBucket",
      "s3:Get*",
      "s3:List*",
      "sdb:BatchPutAttributes",
      "sdb:Select",
      "sqs:CreateQueue",
      "sqs:Delete*",
      "sqs:GetQueue*",
      "sqs:PurgeQueue",
      "sqs:ReceiveMessage",
    ]
    resources = ["*"]
  }
}
resource "aws_iam_role_policy" "iam_emr_service_policy" {
  name   = "zipline_${var.customer_name}_emr_service_policy"
  role   = aws_iam_role.iam_emr_service_role.id
  policy = data.aws_iam_policy_document.iam_emr_service_policy.json
}

# IAM Role for EC2 Instance Profile
data "aws_iam_policy_document" "emr_ec2_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "iam_emr_profile_role" {
  name               = "zipline_${var.customer_name}_emr_profile_role"
  assume_role_policy = data.aws_iam_policy_document.emr_ec2_assume_role.json
}
resource "aws_iam_instance_profile" "emr_profile" {
  name = "zipline_${var.customer_name}_emr_profile"
  role = aws_iam_role.iam_emr_profile_role.name
}
data "aws_iam_policy_document" "iam_emr_profile_policy" {
  statement {
    effect = "Allow"
    actions = [
      "cloudwatch:*",
      "dynamodb:*",
      "ec2:Describe*",
      "elasticmapreduce:Describe*",
      "elasticmapreduce:ListBootstrapActions",
      "elasticmapreduce:ListClusters",
      "elasticmapreduce:ListInstanceGroups",
      "elasticmapreduce:ListInstances",
      "elasticmapreduce:ListSteps",
      "glue:*",
      "kinesis:CreateStream",
      "kinesis:DeleteStream",
      "kinesis:DescribeStream",
      "kinesis:GetRecords",
      "kinesis:GetShardIterator",
      "kinesis:MergeShards",
      "kinesis:PutRecord",
      "kinesis:SplitShard",
      "rds:Describe*",
      "s3:*",
      "sdb:*",
      "sns:*",
      "sqs:*",
    ]
    resources = ["*"]
  }
}
resource "aws_iam_role_policy" "iam_emr_profile_policy" {
  name   = "zipline_${var.customer_name}_emr_profile_policy"
  role   = aws_iam_role.iam_emr_profile_role.id
  policy = data.aws_iam_policy_document.iam_emr_profile_policy.json
}