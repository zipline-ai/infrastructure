# Databricks service principal credentials for Unity Catalog integration.
# In-cluster Spark/Flink jobs read the secrets at startup through NAME_VAULT_URI refs in the team
# env (DATABRICKS_CLIENT_SECRET_VAULT_URI, DATABRICKS_CREDENTIAL_VAULT_URI; wired in locals.tf), so
# the hub never holds or submits them — it only passes the non-secret client ID. Mirrors
# infra-aws-prod#98, adapted to the in-cluster compute roles instead of the EMR Serverless role.
#
# All resources are conditional — only created when databricks_client_id is provided.

locals {
  databricks_enabled = try(trimspace(local.cloud_args.databricks_client_id), "") != ""
}

resource "aws_secretsmanager_secret" "databricks_client_secret" {
  count       = local.databricks_enabled ? 1 : 0
  name        = "${local.name_prefix}-zipline-databricks-client-secret"
  description = "Databricks service principal client secret"
}

resource "aws_secretsmanager_secret_version" "databricks_client_secret" {
  count         = local.databricks_enabled ? 1 : 0
  secret_id     = aws_secretsmanager_secret.databricks_client_secret[0].id
  secret_string = local.cloud_args.databricks_client_secret
}

# client_id:client_secret — the Iceberg REST catalog credential format.
resource "aws_secretsmanager_secret" "databricks_credential" {
  count       = local.databricks_enabled ? 1 : 0
  name        = "${local.name_prefix}-zipline-databricks-credential"
  description = "Databricks service principal client_id:client_secret"
}

resource "aws_secretsmanager_secret_version" "databricks_credential" {
  count         = local.databricks_enabled ? 1 : 0
  secret_id     = aws_secretsmanager_secret.databricks_credential[0].id
  secret_string = "${local.cloud_args.databricks_client_id}:${local.cloud_args.databricks_client_secret}"
}

resource "aws_iam_policy" "databricks_secrets" {
  count       = local.databricks_enabled ? 1 : 0
  name        = "${local.name_prefix}-DatabricksSecretsReadAccess"
  description = "Read the Databricks service principal secrets from Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          aws_secretsmanager_secret.databricks_client_secret[0].arn,
          aws_secretsmanager_secret.databricks_credential[0].arn
        ]
      }
    ]
  })
}

# In-cluster Spark/Flink jobs resolve the vault refs at startup via their pod SA IRSA.
resource "aws_iam_role_policy_attachment" "spark_compute_databricks_secrets" {
  count      = local.databricks_enabled ? 1 : 0
  role       = aws_iam_role.spark_compute_execution.name
  policy_arn = aws_iam_policy.databricks_secrets[0].arn
}

resource "aws_iam_role_policy_attachment" "flink_compute_databricks_secrets" {
  count      = local.databricks_enabled ? 1 : 0
  role       = aws_iam_role.flink_compute_execution.name
  policy_arn = aws_iam_policy.databricks_secrets[0].arn
}

# Hub + eval share the orchestration SA: eval reads the client secret (ESO sync); the hub only
# needs the non-secret client ID but shares the role.
resource "aws_iam_role_policy_attachment" "orchestration_databricks_secrets" {
  count      = local.databricks_enabled ? 1 : 0
  role       = aws_iam_role.orchestration_irsa.name
  policy_arn = aws_iam_policy.databricks_secrets[0].arn
}
