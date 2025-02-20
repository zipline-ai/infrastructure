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

resource "aws_iam_role_policy_attachment" "iam_emr_service_policy" {
  role   = aws_iam_role.iam_emr_service_role.id
  policy_arn = "arn:aws:iam::aws:policy/AmazonEMRServicePolicy_v2"
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
      "cloudwatch:PutMetricData",
      "dynamodb:DescribeTable",
      "dynamodb:GetRecords",
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "glue:GetTable",
      "glue:GetTables",
      "glue:GetPartitions",
      "glue:GetTableVersion",
      "glue:GetTableVersions",
      "glue:GetDatabases",
      "glue:GetDatabase",
      "s3:ListBucket",
      "s3:ListObjects",
      "s3:GetObject",
      "s3:PutObject",
      "s3:UpdateObject",
    ]
    resources = ["*"]
  }
}
resource "aws_iam_role_policy" "iam_emr_profile_policy" {
  name   = "zipline_${var.customer_name}_emr_profile_policy"
  role   = aws_iam_role.iam_emr_profile_role.id
  policy = data.aws_iam_policy_document.iam_emr_profile_policy.json
}