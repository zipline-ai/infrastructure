mock_provider "helm" {}
mock_provider "kubernetes" {}

variables {
  orchestration = {
    deployment = { customer_name = "test", artifact_prefix = "gs://test/artifacts" }
    database   = { host = "postgres" }
    secrets    = { external_secrets_enabled = false }
    install    = { namespace = "custom-system" }
  }
}

run "default_does_not_duplicate_eso_account" {
  command = plan
  assert {
    condition     = length(kubernetes_service_account_v1.secret_store) == 0
    error_message = "The default ESO Helm release owns its account; do not create a duplicate."
  }
}

run "custom_eso_preserves_store_account" {
  command = plan
  variables {
    provider_context = {
      secrets = {
        secret_store_service_account = {
          create = true
          name   = "external-secrets"
          annotations = {
            "iam.gke.io/gcp-service-account" = "test-eso@test-project.iam.gserviceaccount.com"
          }
        }
      }
    }
  }
  assert {
    condition = (
      kubernetes_service_account_v1.secret_store[0].metadata[0].name == "external-secrets" &&
      kubernetes_service_account_v1.secret_store[0].metadata[0].namespace == "custom-system" &&
      kubernetes_service_account_v1.secret_store[0].metadata[0].annotations["iam.gke.io/gcp-service-account"] == "test-eso@test-project.iam.gserviceaccount.com"
    )
    error_message = "The fixed store account must retain its namespace and GCP identity annotation."
  }
}
