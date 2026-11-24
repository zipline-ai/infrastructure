resource "random_password" "redis" {
  count   = local.redis_managed ? 1 : 0
  length  = 48
  special = false
}

resource "aws_secretsmanager_secret" "redis" {
  count                   = local.redis_managed ? 1 : 0
  name                    = "${local.name_prefix}-redis-auth"
  description             = "Authentication token for the Zipline Redis cluster"
  kms_key_id              = local.cloud_args.encryption_kms_key_arn != "" ? local.cloud_args.encryption_kms_key_arn : null
  recovery_window_in_days = local.cloud_args.secret_force_delete ? 0 : 30
}

resource "aws_secretsmanager_secret_version" "redis" {
  count     = local.redis_managed ? 1 : 0
  secret_id = aws_secretsmanager_secret.redis[0].id
  secret_string = jsonencode({
    password = random_password.redis[0].result
  })
}

resource "aws_elasticache_subnet_group" "redis" {
  count      = local.redis_managed ? 1 : 0
  name       = "${local.name_prefix}-redis"
  subnet_ids = [local.resolved_primary_subnet_id, local.resolved_secondary_subnet_id]
}

resource "aws_security_group" "redis" {
  count       = local.redis_managed ? 1 : 0
  name        = "${local.name_prefix}-redis"
  description = "Redis access from Zipline EKS workloads"
  vpc_id      = local.resolved_vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_eks" {
  count                        = local.redis_managed ? 1 : 0
  security_group_id            = aws_security_group.redis[0].id
  referenced_security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  description                  = "Redis from EKS nodes and workloads"
}

resource "aws_elasticache_replication_group" "redis" {
  count                      = local.redis_managed ? 1 : 0
  replication_group_id       = "${local.name_prefix}-redis"
  description                = "Zipline Chronon Redis KV store"
  engine                     = "redis"
  engine_version             = "7.1"
  node_type                  = local.redis.node_type
  port                       = 6379
  parameter_group_name       = "default.redis7.cluster.on"
  num_node_groups            = local.redis.shards
  replicas_per_node_group    = local.redis.replicas_per_shard
  automatic_failover_enabled = local.redis.replicas_per_shard > 0
  multi_az_enabled           = local.redis.replicas_per_shard > 0
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = random_password.redis[0].result
  auth_token_update_strategy = "ROTATE"
  subnet_group_name          = aws_elasticache_subnet_group.redis[0].name
  security_group_ids         = [aws_security_group.redis[0].id]
  apply_immediately          = true
  kms_key_id                 = local.cloud_args.encryption_kms_key_arn != "" ? local.cloud_args.encryption_kms_key_arn : null
}
