mock_provider "helm" {}
mock_provider "kubernetes" {}

variables {
  orchestration = {
    deployment = { customer_name = "test", artifact_prefix = "s3://test/artifacts" }
    database   = { host = "postgres" }
    secrets    = { external_secrets_enabled = false }
  }
}

run "no_keys_required" {
  command = plan
  variables {
    orchestration = merge(var.orchestration, { agents = { enable = true } })
  }
  assert {
    condition     = length(local.agents_remote_refs) == 0
    error_message = "Enabled agents must not require deployment-level provider credentials."
  }
}

run "disabled_ignores_refs" {
  command = plan
  variables {
    orchestration = merge(var.orchestration, {
      agents = {
        enable                       = false
        anthropic_api_key_remote_ref = { key = "unused" }
      }
    })
  }
  assert {
    condition     = length(local.agents_remote_refs) == 0 && !contains([for target in local.external_secret_targets : target.name], "agents-provider-credentials")
    error_message = "Disabled agents must not sync provider credentials."
  }
}

run "both_providers" {
  command = plan
  variables {
    orchestration = merge(var.orchestration, {
      agents = {
        enable                       = true
        anthropic_api_key_remote_ref = { key = "provider-keys", property = "anthropic" }
        openai_api_key_remote_ref    = { key = "openai-key" }
      }
    })
  }
  assert {
    condition     = length(local.agents_external_secret.spec.data) == 2 && contains([for target in local.external_secret_targets : target.name], "agents-provider-credentials")
    error_message = "Configured provider keys must be included in External Secret targets."
  }
  assert {
    condition     = local.agents_remote_refs.AGENTS_ANTHROPIC_API_KEY.property == "anthropic"
    error_message = "JSON property references must be preserved."
  }
  assert {
    condition = alltrue([for name in ["AGENTS_ANTHROPIC_API_KEY", "AGENTS_OPENAI_API_KEY"] :
      contains(local.common_values.orchestration.ui.env, {
        name      = name
        valueFrom = { secretKeyRef = { name = "agents-provider-credentials", key = name } }
      })
    ])
    error_message = "Both UI keys must use secretKeyRef, without plaintext values."
  }
}

run "single_provider" {
  command = plan
  variables {
    orchestration = merge(var.orchestration, {
      agents = {
        enable                    = true
        openai_api_key_remote_ref = { key = "openai-key" }
      }
    })
  }
  assert {
    condition     = length(local.agents_remote_refs) == 1 && !contains([for env in local.common_values.orchestration.ui.env : env.name], "AGENTS_ANTHROPIC_API_KEY")
    error_message = "A single provider must not require the other provider's Secret key."
  }
}
