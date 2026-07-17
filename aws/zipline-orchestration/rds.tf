resource "aws_db_subnet_group" "zipline" {
  name        = "${local.name_prefix}-zipline-subnet-group"
  subnet_ids  = [local.resolved_primary_subnet_id, local.resolved_secondary_subnet_id]
  description = "Subnet group for the Zipline orchestration RDS instance"
}

resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"

  lifecycle {
    ignore_changes = [override_special]
  }
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${local.name_prefix}-zipline-db-password"
  description             = "Database credentials for the Zipline orchestration RDS instance"
  kms_key_id              = local.cloud_args.encryption_kms_key_arn != "" ? local.cloud_args.encryption_kms_key_arn : null
  recovery_window_in_days = local.cloud_args.secret_force_delete ? 0 : 30
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = local.cloud_args.database_username
    password = random_password.db_password.result
  })
}

resource "aws_db_instance" "zipline" {
  identifier              = "${local.name_prefix}-zipline-orch-instance"
  engine                  = "postgres"
  instance_class          = local.cloud_args.database_instance_class
  allocated_storage       = local.cloud_args.database_allocated_storage
  db_name                 = local.cloud_args.database_name
  username                = local.cloud_args.database_username
  password                = random_password.db_password.result
  storage_encrypted       = true
  kms_key_id              = local.cloud_args.encryption_kms_key_arn != "" ? local.cloud_args.encryption_kms_key_arn : null
  db_subnet_group_name    = aws_db_subnet_group.zipline.name
  vpc_security_group_ids  = [aws_security_group.zipline.id]
  publicly_accessible     = local.cloud_args.database_publicly_accessible
  multi_az                = local.cloud_args.database_multi_az
  backup_retention_period = local.cloud_args.database_backup_retention_days

  # Default false so prod takes a final snapshot on destroy (and thus needs a
  # snapshot id); test/POC accounts override to true for snapshot-free teardown.
  skip_final_snapshot       = local.cloud_args.database_skip_final_snapshot
  final_snapshot_identifier = local.cloud_args.database_skip_final_snapshot ? null : "${local.name_prefix}-zipline-orch-final"
}
