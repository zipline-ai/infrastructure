mock_provider "helm" {}
mock_provider "kubernetes" {}

variables {
  orchestration = {
    deployment = {
      customer_name   = "test"
      artifact_prefix = "s3://test/artifacts"
    }
    database = { host = "primary" }
    secrets  = { external_secrets_enabled = false }
  }
}

run "default_disabled" {
  command = plan
  assert {
    condition     = yamldecode(reverse(helm_release.this.values)[0]).orchestration.readOnly.enabled == false
    error_message = "Read-only servers must be opt-in."
  }
}

run "provider_replica_wiring" {
  command = plan
  variables {
    orchestration = merge(var.orchestration, {
      read_only = {
        enabled = true
        ingress = { enabled = true, host = "reader.example.com" }
      }
    })
    provider_context = {
      read_only = {
        database_host  = "replica"
        verticle_class = "ai.chronon.hub.AWSOrchestrationVerticle"
      }
    }
  }
  assert {
    condition     = yamldecode(reverse(helm_release.this.values)[0]).orchestration.readOnly.databaseHost == "replica"
    error_message = "Reader must use the cloud-provided replica address."
  }
  assert {
    condition     = yamldecode(reverse(helm_release.this.values)[0]).orchestration.readOnly.ingress.host == "reader.example.com"
    error_message = "The reader ingress must keep its explicit hostname."
  }
  assert {
    condition     = yamldecode(helm_release.this.values[0]).database.host == "primary"
    error_message = "Enabling the reader must not change the primary database connection."
  }
}

run "missing_replica_rejected" {
  command = plan
  variables {
    orchestration = merge(var.orchestration, {
      read_only = { enabled = true, verticle_class = "test.Http" }
    })
  }
  expect_failures = [terraform_data.read_only_configuration]
}

run "primary_host_rejected" {
  command = plan
  variables {
    orchestration = merge(var.orchestration, {
      read_only = { enabled = true, database_host = "primary", verticle_class = "test.Http" }
    })
  }
  expect_failures = [terraform_data.read_only_configuration]
}

run "worker_verticles_rejected" {
  command = plan
  variables {
    orchestration = merge(var.orchestration, {
      read_only = { enabled = true, database_host = "replica", verticle_class = "test.Http,test.Worker" }
    })
  }
  expect_failures = [terraform_data.read_only_configuration]
}

run "extra_values_cannot_redirect_reader" {
  command = plan
  variables {
    orchestration = merge(var.orchestration, {
      read_only         = { enabled = true, database_host = "replica", verticle_class = "test.Http" }
      extra_values_yaml = ["orchestration:\n  readOnly:\n    enabled: false\n    databaseHost: primary\n"]
    })
  }
  assert {
    condition     = yamldecode(reverse(helm_release.this.values)[0]).orchestration.readOnly.enabled && yamldecode(reverse(helm_release.this.values)[0]).orchestration.readOnly.databaseHost == "replica"
    error_message = "Generic Helm overrides must not change the reader's enablement or replica host."
  }
}
