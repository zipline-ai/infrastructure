mock_provider "helm" {}
mock_provider "kubernetes" {}

variables {
  orchestration = {
    deployment = { customer_name = "test", artifact_prefix = "s3://test/artifacts" }
    database   = { host = "postgres" }
    secrets    = { external_secrets_enabled = false }
  }
}

run "team_namespaces_off_by_default" {
  command = plan
  assert {
    condition     = local.common_values.compute.teamNamespaces.enabled == false
    error_message = "Hub-created team namespaces must stay off unless a deployment opts in."
  }
}

run "team_namespaces_enabled" {
  command = plan
  variables {
    orchestration = {
      deployment = { customer_name = "test", artifact_prefix = "s3://test/artifacts" }
      database   = { host = "postgres" }
      secrets    = { external_secrets_enabled = false }
      compute    = { team_namespaces_enabled = true }
    }
  }
  assert {
    condition     = local.common_values.compute.teamNamespaces.enabled == true
    error_message = "compute.team_namespaces_enabled must reach the chart as compute.teamNamespaces.enabled."
  }
}
