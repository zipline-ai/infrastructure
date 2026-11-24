mock_provider "helm" {}
mock_provider "kubernetes" {}

variables {
  orchestration = {
    deployment = { customer_name = "test", artifact_prefix = "s3://test/artifacts" }
    database   = { host = "postgres" }
    secrets    = { external_secrets_enabled = false }
  }
}

run "omitted" {
  command = plan
  assert {
    condition     = length([for env in local.common_values.orchestration.ui.env : env if startswith(env.name, "AGENTS")]) == 0
    error_message = "Agents environment variables must be absent by default."
  }
}

run "disabled" {
  command = plan
  variables {
    orchestration = merge(var.orchestration, { agents = { enable = false, llm_proxy_url = "http://custom-proxy:8080" } })
  }
  assert {
    condition     = length([for env in local.common_values.orchestration.ui.env : env if startswith(env.name, "AGENTS")]) == 0
    error_message = "Disabling agents must omit both environment variables even with a configured URL."
  }
}

run "enabled" {
  command = plan
  variables {
    orchestration = merge(var.orchestration, {
      agents = { enable = true }
      ui_env = [{ name = "EXISTING_UI_ENV", value = "preserved" }]
    })
  }
  assert {
    condition = alltrue([
      contains(local.common_values.orchestration.ui.env, { name = "AGENTS", value = "true" }),
      contains(local.common_values.orchestration.ui.env, { name = "AGENTS_LLM_PROXY_URL", value = "http://orchestration-ui-service" }),
      contains(local.common_values.orchestration.ui.env, { name = "EXISTING_UI_ENV", value = "preserved" }),
    ])
    error_message = "Enabling agents must set the internal UI endpoint and preserve existing UI environment variables."
  }
}

run "custom_proxy" {
  command = plan
  variables {
    orchestration = merge(var.orchestration, { agents = { enable = true, llm_proxy_url = "http://custom-proxy:8080" } })
  }
  assert {
    condition     = contains(local.common_values.orchestration.ui.env, { name = "AGENTS_LLM_PROXY_URL", value = "http://custom-proxy:8080" })
    error_message = "The proxy URL override must reach the UI."
  }
}

run "reject_non_boolean" {
  command = plan
  variables {
    orchestration = merge(var.orchestration, { agents = { enable = "true" } })
  }
  expect_failures = [var.orchestration]
}
