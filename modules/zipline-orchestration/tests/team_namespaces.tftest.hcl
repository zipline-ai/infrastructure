mock_provider "helm" {}
mock_provider "kubernetes" {}

variables {
  orchestration = {
    deployment = { customer_name = "test", artifact_prefix = "s3://test/artifacts" }
    database   = { host = "postgres" }
    secrets    = { external_secrets_enabled = false }
  }
}

run "team_namespaces_follow_compute_installation" {
  command = plan
  assert {
    condition     = !contains(keys(local.common_values.compute), "teamNamespaces") && !contains(keys(local.compute_defaults), "team_namespaces_enabled")
    error_message = "Team namespace provisioning is part of in-cluster compute and must not have a separate switch."
  }
  assert {
    condition     = local.common_values.compute.rbac.create == true
    error_message = "Compute installation must grant namespace provisioning RBAC by default."
  }
}

run "externally_managed_compute_rbac" {
  command = plan
  variables {
    orchestration = {
      deployment = { customer_name = "test", artifact_prefix = "s3://test/artifacts" }
      database   = { host = "postgres" }
      secrets    = { external_secrets_enabled = false }
      compute    = { rbac_create = false }
    }
  }
  assert {
    condition     = local.common_values.compute.rbac.create == false && !contains(keys(local.common_values.compute), "teamNamespaces")
    error_message = "Externally managed RBAC must remain supported without disabling the team namespace template."
  }
}
