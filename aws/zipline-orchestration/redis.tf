resource "aws_elasticache_subnet_group" "fetcher" {
  count = local.deploy_fetcher ? 1 : 0

  name       = "${local.name_prefix}-fetcher"
  subnet_ids = [local.resolved_primary_subnet_id, local.resolved_secondary_subnet_id]
}

resource "aws_security_group" "fetcher_redis" {
  count = local.deploy_fetcher ? 1 : 0

  name        = "${local.name_prefix}-fetcher-redis"
  description = "Allow the Zipline EKS cluster to reach the fetcher Redis cluster"
  vpc_id      = local.resolved_vpc_id

  tags = {
    Name = "${local.name_prefix}-fetcher-redis"
  }
}

resource "aws_vpc_security_group_ingress_rule" "fetcher_redis_from_eks" {
  count = local.deploy_fetcher ? 1 : 0

  security_group_id            = aws_security_group.fetcher_redis[0].id
  referenced_security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
}

resource "aws_elasticache_replication_group" "fetcher" {
  count = local.deploy_fetcher ? 1 : 0

  replication_group_id = "${local.name_prefix}-fetcher"
  description          = "Redis cluster for the Zipline fetcher"
  engine               = "redis"
  engine_version       = local.cloud_args.fetcher_redis_engine_version
  node_type            = local.cloud_args.fetcher_redis_node_type
  port                 = 6379

  parameter_group_name       = "default.redis7.cluster.on"
  num_node_groups            = 1
  replicas_per_node_group    = 0
  automatic_failover_enabled = false
  multi_az_enabled           = false

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  subnet_group_name          = aws_elasticache_subnet_group.fetcher[0].name
  security_group_ids         = [aws_security_group.fetcher_redis[0].id]

  apply_immediately = true
}
