mock_provider "google" {
  mock_resource "google_service_account" {
    defaults = {
      name  = "projects/test-project/serviceAccounts/test-eso@test-project.iam.gserviceaccount.com"
      email = "test-eso@test-project.iam.gserviceaccount.com"
    }
  }
  mock_resource "google_compute_network" {
    defaults = { self_link = "projects/test-project/global/networks/test-vpc" }
  }
}
mock_provider "google-beta" {}
mock_provider "kubernetes" {}
mock_provider "helm" {}
mock_provider "random" {}

variables {
  gcp = { project_id = "test-project", region = "us-central1" }
  orchestration = {
    deployment = { customer_name = "test", zipline_version = "test" }
  }
}

run "default_account_owned_by_eso" {
  command = plan
  assert {
    condition = (
      !local.provider_context.secrets.secret_store_service_account.create &&
      local.provider_addons.external_secrets_operator_values.serviceAccount.annotations["iam.gke.io/gcp-service-account"] == google_service_account.external_secrets.email
    )
    error_message = "The default ESO account must stay annotated without creating a duplicate."
  }
}

run "custom_values_preserve_annotation" {
  command = plan
  variables {
    orchestration = {
      deployment = { customer_name = "test", zipline_version = "test" }
      addons = {
        external_secrets_operator_values = {
          replicaCount = 2
          serviceAccount = {
            name = "custom-eso"
            annotations = {
              "example.com/owner"              = "platform"
              "iam.gke.io/gcp-service-account" = "incorrect@example-project.iam.gserviceaccount.com"
            }
          }
        }
      }
    }
  }
  assert {
    condition = (
      local.provider_context.secrets.secret_store_service_account.create &&
      local.provider_context.secrets.secret_store_service_account.name == "external-secrets" &&
      local.provider_context.secrets.secret_store_service_account.annotations["iam.gke.io/gcp-service-account"] == google_service_account.external_secrets.email &&
      local.provider_addons.external_secrets_operator_values.serviceAccount.name == "custom-eso" &&
      local.provider_addons.external_secrets_operator_values.serviceAccount.annotations["iam.gke.io/gcp-service-account"] == google_service_account.external_secrets.email &&
      local.provider_addons.external_secrets_operator_values.serviceAccount.annotations["example.com/owner"] == "platform" &&
      local.provider_addons.external_secrets_operator_values.replicaCount == 2
    )
    error_message = "Custom ESO settings must keep both the operator and fixed store identity available."
  }
}

run "empty_custom_values_preserve_annotation" {
  command = plan
  variables {
    orchestration = {
      deployment = { customer_name = "test", zipline_version = "test" }
      addons     = { external_secrets_operator_values = {} }
    }
  }
  assert {
    condition = (
      !local.provider_context.secrets.secret_store_service_account.create &&
      local.provider_addons.external_secrets_operator_values.serviceAccount.annotations["iam.gke.io/gcp-service-account"] == google_service_account.external_secrets.email
    )
    error_message = "An empty custom map must not remove the default identity annotation."
  }
}
