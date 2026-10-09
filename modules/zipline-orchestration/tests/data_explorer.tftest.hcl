mock_provider "helm" {}
mock_provider "kubernetes" {}

variables {
  orchestration = {
    deployment = {
      customer_name   = "test"
      artifact_prefix = "s3://test/artifacts"
    }
    database = { host = "postgres" }
    secrets  = { external_secrets_enabled = false }
  }
}

run "default_disabled" {
  command = plan

  assert {
    condition     = length(helm_release.starrocks) == 0
    error_message = "Omitting the option must not deploy StarRocks or require its storage configuration."
  }
  assert {
    condition     = yamldecode(reverse(helm_release.this.values)[0]).dataExplorer.enabled == false
    error_message = "The UI and catalog job must be disabled by default."
  }
}

run "enabled" {
  command = plan
  variables {
    orchestration = merge(var.orchestration, {
      data_explorer     = { enabled = true }
      values            = { starrocks = { feConfig = { run_mode = "shared_data" } } }
      extra_values_yaml = ["dataExplorer:\n  enabled: false\n"]
    })
  }
  assert {
    condition     = length(helm_release.starrocks) == 1
    error_message = "Enabling Data Explorer must deploy StarRocks."
  }
  assert {
    condition     = yamldecode(reverse(helm_release.this.values)[0]).dataExplorer.enabled == true
    error_message = "Additional Helm values must not disable the UI independently of StarRocks."
  }
}

run "explicitly_disabled" {
  command = plan
  variables {
    orchestration = merge(var.orchestration, {
      data_explorer     = { enabled = false }
      extra_values_yaml = ["dataExplorer:\n  enabled: true\n"]
    })
  }
  assert {
    condition     = length(helm_release.starrocks) == 0
    error_message = "Disabling Data Explorer must not deploy StarRocks."
  }
  assert {
    condition     = yamldecode(reverse(helm_release.this.values)[0]).dataExplorer.enabled == false
    error_message = "Additional Helm values must not enable the UI without StarRocks."
  }
}

run "enabled_requires_storage" {
  command = plan
  variables {
    orchestration = merge(var.orchestration, { data_explorer = { enabled = true } })
  }
  expect_failures = [terraform_data.configuration_validation]
}

run "reject_non_boolean" {
  command = plan
  variables {
    orchestration = merge(var.orchestration, { data_explorer = { enabled = "false" } })
  }
  expect_failures = [var.orchestration]
}
