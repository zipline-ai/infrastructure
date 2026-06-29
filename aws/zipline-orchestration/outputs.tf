output "eks_cluster_name" {
  description = "EKS cluster name."
  value       = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster API endpoint."
  value       = aws_eks_cluster.main.endpoint
}

output "eks_cluster_arn" {
  description = "EKS cluster ARN."
  value       = aws_eks_cluster.main.arn
}

output "kubeconfig_command" {
  description = "Command to configure kubectl for this cluster."
  value       = "aws eks update-kubeconfig --region ${local.cloud_args.region} --name ${aws_eks_cluster.main.name}"
}

output "rds_endpoint" {
  description = "RDS endpoint for the Zipline orchestration database."
  value       = aws_db_instance.zipline.endpoint
}

output "rds_secret_arn" {
  description = "Secrets Manager ARN for database credentials."
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "artifact_bucket_name" {
  description = "S3 bucket used for Zipline artifacts."
  value       = aws_s3_bucket.artifact.id
}

output "warehouse_bucket_name" {
  description = "S3 bucket used for the Zipline warehouse."
  value       = aws_s3_bucket.warehouse.id
}

output "logs_bucket_name" {
  description = "S3 bucket used for Zipline logs."
  value       = aws_s3_bucket.logs.id
}

output "orchestration_irsa_role_arn" {
  description = "IAM role ARN used by orchestration services."
  value       = aws_iam_role.orchestration_irsa.arn
}

output "spark_compute_role_arn" {
  description = "IAM role ARN used by Spark compute pods."
  value       = aws_iam_role.spark_compute_execution.arn
}

output "flink_compute_role_arn" {
  description = "IAM role ARN used by Flink compute pods."
  value       = aws_iam_role.flink_compute_execution.arn
}

output "polaris_storage_role_arn" {
  description = "IAM role ARN used by Polaris storage credential vending."
  value       = aws_iam_role.polaris_storage.arn
}

output "chronon_metadata_table_name" {
  description = "DynamoDB table name for Chronon metadata."
  value       = aws_dynamodb_table.chronon_metadata.name
}

output "table_partitions_table_name" {
  description = "DynamoDB table name for table partitions."
  value       = aws_dynamodb_table.table_partitions.name
}

output "amp_workspace_arn" {
  description = "AWS Managed Prometheus workspace ARN."
  value       = aws_prometheus_workspace.main.arn
}

output "amp_query_endpoint" {
  description = "AWS Managed Prometheus query endpoint."
  value       = aws_prometheus_workspace.main.prometheus_endpoint
}

output "ingress_load_balancer_hostname" {
  description = "Load balancer hostname for the public ingress controller."
  value       = module.zipline_orchestration.ingress_load_balancer_hostname
}

output "ingress_load_balancer_ip" {
  description = "Load balancer IP for the public ingress controller."
  value       = module.zipline_orchestration.ingress_load_balancer_ip
}

output "ingress_load_balancer_target" {
  description = "Provider-neutral DNS target for the public ingress controller."
  value       = module.zipline_orchestration.ingress_load_balancer_target
}
