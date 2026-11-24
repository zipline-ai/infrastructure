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

# Secrets Manager can report a key ID, ARN, or alias. Resolve it to a key ARN
# before using it as an IAM resource. Default encryption omits kms_key_id.
data "aws_kms_key" "databricks" {
  for_each = {
    for name, secret in data.aws_secretsmanager_secret.databricks : name => secret.kms_key_id
    if try(trimspace(secret.kms_key_id), "") != ""
  }

  key_id = each.value
}
