mock_provider "helm" {}
mock_provider "kubernetes" {}

run "ui_env_names_are_unique_last_wins" {
  command = plan
  variables {
    orchestration = {
      deployment = {
        customer_name   = "test"
        artifact_prefix = "gs://test/artifacts"
      }
      database = { host = "postgres" }
      secrets  = { external_secrets_enabled = false }
      ui_env   = [{ name = "LOG_PROVIDER", value = "loki" }]
    }
    provider_context = {
      metrics_provider = "gcp"
      ui_env = [
        { name = "METRICS_PROVIDER", value = "gcp" },
        { name = "LOG_PROVIDER", value = "gcp" },
      ]
    }
  }

  assert {
    condition     = length(local.ui_env) == length(distinct([for e in local.ui_env : e.name]))
    error_message = "UI env names must be unique."
  }
  assert {
    condition     = [for e in local.ui_env : e.value if e.name == "LOG_PROVIDER"] == ["loki"]
    error_message = "orchestration.ui_env must win over the provider's LOG_PROVIDER."
  }
}
