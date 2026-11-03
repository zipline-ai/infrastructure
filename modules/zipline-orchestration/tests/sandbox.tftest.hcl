mock_provider "helm" {}
mock_provider "kubernetes" {}

variables {
  orchestration = {
    deployment = { customer_name = "test", artifact_prefix = "s3://test/artifacts" }
    database   = { host = "postgres" }
    secrets    = { external_secrets_enabled = false }
  }
}

run "sandbox_disabled" {
  command = plan
  assert {
    condition     = local.common_values.orchestration.confRepo.url == "" && length(local.conf_repo_remote_refs) == 0
    error_message = "An absent repository must not enable sandbox or sync credentials."
  }
}

run "sandbox_enabled" {
  command = plan
  variables {
    orchestration = merge(var.orchestration, {
      conf_repo = {
        url                             = "https://github.com/example/conf"
        path                            = "python/conf"
        branch                          = "deploy"
        zipline_env                     = "canary"
        github_client_id                = "client"
        github_token_remote_ref         = { key = "test-token" }
        github_client_secret_remote_ref = { key = "test-client-secret" }
      }
    })
  }
  assert {
    condition     = local.common_values.orchestration.confRepo.tokenKey == "github-token" && local.common_values.orchestration.confRepo.clientSecretKey == "github-client-secret"
    error_message = "Both GitHub credentials must reach the UI as secret references."
  }
  assert {
    condition     = local.common_values.orchestration.confRepo.path == "python/conf" && local.common_values.orchestration.confRepo.ziplineEnv == "canary"
    error_message = "Repository configuration must pass through Terraform to Helm."
  }
  assert {
    condition     = length(local.conf_repo_external_secret.spec.data) == 2
    error_message = "Both cloud secret references must be synced."
  }
}

run "token_only" {
  command = plan
  variables {
    orchestration = merge(var.orchestration, {
      conf_repo = {
        url                     = "https://github.com/example/conf"
        github_token_remote_ref = { key = "test-token", property = "token" }
      }
    })
  }
  assert {
    condition     = length(local.conf_repo_external_secret.spec.data) == 1 && local.common_values.orchestration.confRepo.clientSecretKey == ""
    error_message = "A token-only configuration must not require an OAuth client secret."
  }
}
