resource "random_password" "zipline_auth" {
  count   = local.create_auth_secret ? 1 : 0
  length  = 48
  special = false
}

resource "aws_secretsmanager_secret" "zipline_auth" {
  count       = local.create_auth_secret ? 1 : 0
  name        = "${local.name_prefix}-zipline-auth"
  description = "Authentication secrets for Zipline"
  kms_key_id  = local.cloud_args.encryption_kms_key_arn != "" ? local.cloud_args.encryption_kms_key_arn : null
}

resource "aws_secretsmanager_secret_version" "zipline_auth" {
  count     = local.create_auth_secret ? 1 : 0
  secret_id = aws_secretsmanager_secret.zipline_auth[0].id
  secret_string = jsonencode({
    "auth-secret"                         = try(local.cloud_args.auth_secret_values.auth_secret, random_password.zipline_auth[0].result)
    "google-oauth-client-secret"          = try(local.cloud_args.auth_secret_values.google_oauth_client_secret, "")
    "github-oauth-client-secret"          = try(local.cloud_args.auth_secret_values.github_oauth_client_secret, "")
    "microsoft-entra-oauth-client-secret" = try(local.cloud_args.auth_secret_values.microsoft_entra_oauth_client_secret, "")
    "sso-client-secret"                   = try(local.cloud_args.auth_secret_values.sso_client_secret, "")
    "sso-saml-cert"                       = try(local.cloud_args.auth_secret_values.sso_saml_cert, "")
  })
}
