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

run "fullname_override" {
  command = plan
  variables {
    orchestration = {
      deployment = { customer_name = "test", zipline_version = "test" }
      addons     = { external_secrets_operator_values = { fullnameOverride = "custom-eso" } }
    }
  }
  assert {
    condition = (
      local.eso_service_account_name == "custom-eso" &&
      local.provider_context.secrets.secret_store_service_account.create == true &&
      local.provider_context.secrets.secret_store_service_account.name == "external-secrets" &&
      local.provider_context.secrets.secret_store.spec.provider.gcpsm.auth.workloadIdentity.serviceAccountRef.name == "external-secrets"
    )
    error_message = "Resolve the chart account name without losing the fixed store identity or duplicating the default account."
  }
}

run "explicit_name_overrides_fullname" {
  command = plan
  variables {
    orchestration = {
      deployment = { customer_name = "test", zipline_version = "test" }
      addons     = { external_secrets_operator_values = { fullnameOverride = "custom-eso", serviceAccount = { name = "external-secrets" } } }
    }
  }
  assert {
    condition = (
      local.eso_service_account_name == "external-secrets" &&
      local.provider_context.secrets.secret_store_service_account.create == false &&
      local.provider_context.secrets.secret_store_service_account.name == "external-secrets" &&
      local.provider_context.secrets.secret_store.spec.provider.gcpsm.auth.workloadIdentity.serviceAccountRef.name == "external-secrets"
    )
    error_message = "Resolve the chart account name without losing the fixed store identity or duplicating the default account."
  }
}

run "fullname_truncates_and_trims" {
  command = plan
  variables {
    orchestration = {
      deployment = { customer_name = "test", zipline_version = "test" }
      addons     = { external_secrets_operator_values = { fullnameOverride = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx-suffix" } }
    }
  }
  assert {
    condition = (
      local.eso_service_account_name == "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" &&
      local.provider_context.secrets.secret_store_service_account.create == true &&
      local.provider_context.secrets.secret_store_service_account.name == "external-secrets" &&
      local.provider_context.secrets.secret_store.spec.provider.gcpsm.auth.workloadIdentity.serviceAccountRef.name == "external-secrets"
    )
    error_message = "Resolve the chart account name without losing the fixed store identity or duplicating the default account."
  }
}

run "name_override" {
  command = plan
  variables {
    orchestration = {
      deployment = { customer_name = "test", zipline_version = "test" }
      addons     = { external_secrets_operator_values = { nameOverride = "custom" } }
    }
  }
  assert {
    condition = (
      local.eso_service_account_name == "external-secrets-custom" &&
      local.provider_context.secrets.secret_store_service_account.create == true &&
      local.provider_context.secrets.secret_store_service_account.name == "external-secrets" &&
      local.provider_context.secrets.secret_store.spec.provider.gcpsm.auth.workloadIdentity.serviceAccountRef.name == "external-secrets"
    )
    error_message = "Resolve the chart account name without losing the fixed store identity or duplicating the default account."
  }
}

run "externally_managed_default" {
  command = plan
  variables {
    orchestration = {
      deployment = { customer_name = "test", zipline_version = "test" }
      addons     = { external_secrets_operator_values = { serviceAccount = { create = false } } }
    }
  }
  assert {
    condition = (
      local.eso_service_account_name == "default" &&
      local.provider_context.secrets.secret_store_service_account.create == true &&
      local.provider_context.secrets.secret_store_service_account.name == "external-secrets" &&
      local.provider_context.secrets.secret_store.spec.provider.gcpsm.auth.workloadIdentity.serviceAccountRef.name == "external-secrets"
    )
    error_message = "Resolve the chart account name without losing the fixed store identity or duplicating the default account."
  }
}

run "external_eso_leaves_accounts_unmanaged" {
  command = plan
  variables {
    orchestration = {
      deployment = { customer_name = "test", zipline_version = "test" }
      addons = {
        install_external_secrets_operator = false
        external_secrets_operator_values  = { serviceAccount = { name = "custom-eso" } }
      }
    }
  }
  assert {
    condition     = !local.provider_context.secrets.secret_store_service_account.create
    error_message = "An external ESO installation must not imply wrapper ownership of its store account."
  }
}

run "explicitly_adopt_external_store_account" {
  command = plan
  variables {
    gcp = {
      project_id                          = "test-project"
      region                              = "us-central1"
      create_secret_store_service_account = true
    }
    orchestration = {
      deployment = { customer_name = "test", zipline_version = "test" }
      addons     = { install_external_secrets_operator = false }
    }
  }
  assert {
    condition     = local.provider_context.secrets.secret_store_service_account.create
    error_message = "Explicit wrapper ownership must allow importing an external fixed-name account."
  }
}

run "explicitly_leave_store_account_external" {
  command = plan
  variables {
    gcp = {
      project_id                          = "test-project"
      region                              = "us-central1"
      create_secret_store_service_account = false
    }
    orchestration = {
      deployment = { customer_name = "test", zipline_version = "test" }
      addons     = { external_secrets_operator_values = { serviceAccount = { name = "custom-eso" } } }
    }
  }
  assert {
    condition     = !local.provider_context.secrets.secret_store_service_account.create
    error_message = "Explicit external ownership must prevent account creation even for a custom ESO name."
  }
}

run "explicit_ownership_does_not_duplicate_helm_account" {
  command = plan
  variables {
    gcp = {
      project_id                          = "test-project"
      region                              = "us-central1"
      create_secret_store_service_account = true
    }
  }
  assert {
    condition     = !local.provider_context.secrets.secret_store_service_account.create
    error_message = "Explicit ownership must not create a duplicate of the default Helm-owned account."
  }
}
