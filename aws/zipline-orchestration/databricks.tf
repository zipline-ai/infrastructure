# Read metadata only: never fetch Databricks secret values into Terraform state.
# With tfvars inputs, these reads fail during planning if the secrets cannot be
# described. Compare the resolved ARN because AWS can accept partial ARNs.
data "aws_secretsmanager_secret" "databricks" {
  for_each = try(trimspace(local.cloud_args.databricks_client_id), "") == "" ? {} : {
    client_secret = local.cloud_args.databricks_client_secret_arn
    credential    = local.cloud_args.databricks_credential_arn
  }

  arn = each.value

  lifecycle {
    postcondition {
      condition     = self.id == each.value
      error_message = "Databricks secret references must be complete Secrets Manager ARNs, including the six-character suffix; the resolved ARN differs from the supplied ARN."
    }
  }
}
