locals {
  azure = merge({
    database_password_secret_name = "pg-admin-password"
    database_username_secret_name = "pg-admin-username"
    storage_path_prefix           = ""
    ingress_load_balancer_ip      = ""
    load_balancer_resource_group  = ""
  }, var.azure)

  auth_saml_enabled = try(var.orchestration.auth.sso_use_saml, false)
  auth_secret_keys = concat(
    [
      "auth-secret",
      "google-oauth-client-secret",
      "github-oauth-client-secret",
      "microsoft-entra-oauth-client-secret",
      "sso-client-secret",
    ],
    local.auth_saml_enabled ? ["sso-saml-cert"] : [],
  )

  compute_input = merge({ spark_event_log_dir = "", flink_service_account = "flink", default_namespace = "zipline-default" }, try(var.orchestration.compute, {}))

  orchestration = merge(var.orchestration, {
    hub = merge(try(var.orchestration.hub, {}), {
      image          = local.hub_image
      verticle_class = local.hub_verticle_class
    })
    eval = merge(try(var.orchestration.eval, {}), {
      image = local.eval_image
    })
    compute = merge(local.compute_input, {
      object_store = {
        bucket = local.azure.warehouse_container_name
        region = local.azure.location
      }
      spark_event_log_dir = local.spark_event_log_dir
      service_account = merge(try(local.compute_input.service_account, {}), {
        annotations = local.workload_identity_annotations
      })
      flink_defaults = merge(try(local.compute_input.flink_defaults, {}), {
        serviceAccountAnnotations = local.workload_identity_annotations
      })
      history_server_options = concat(local.spark_history_opts, try(local.compute_input.history_server_options, []))
    })
    image_pull_secret = merge({
      name = ""
    }, try(var.orchestration.image_pull_secret, {}))
    ingress = merge({
      class_name                  = "nginx-ui"
      tls_secret_name             = "zipline-tls-secret"
      cert_manager_cluster_issuer = "letsencrypt-prod"
      annotations                 = {}
    }, var.orchestration.ingress)
    addons = merge({
      install_secrets_store_csi_driver = false
    }, try(var.orchestration.addons, {}))
    secrets = merge(try(var.orchestration.secrets, {}), {
      database_object_names = merge({
        username = local.azure.database_username_secret_name
        password = local.azure.database_password_secret_name
      }, try(var.orchestration.secrets.database_object_names, {}))
    })
    provider_service_account_annotations = local.workload_identity_annotations
    provider_runtime_env                 = local.runtime_env
    provider_hub_env                     = local.hub_env
    values                               = local.provider_values
  })

  deployment = var.orchestration.deployment

  normalized_storage_path     = trim(local.azure.storage_path_prefix, "/")
  storage_path_prefix_segment = local.normalized_storage_path == "" ? "" : "${local.normalized_storage_path}/"
  abfs_base_uri               = "abfss://${local.azure.warehouse_container_name}@${local.azure.storage_account_name}.dfs.core.windows.net/${local.storage_path_prefix_segment}"
  spark_event_log_dir         = local.compute_input.spark_event_log_dir != "" ? local.compute_input.spark_event_log_dir : "${local.abfs_base_uri}spark-events"
  polaris_base_location       = "${local.abfs_base_uri}polaris/polaris_${local.deployment.customer_name}/"
  hub_image                   = "ziplineai/hub-azure"
  eval_image                  = "ziplineai/eval-azure"
  hub_verticle_class          = "ai.chronon.hub.AzureOrchestrationVerticle,ai.chronon.hub.AzureWorkflowExecutionVerticle"
  auth_enabled                = try(var.orchestration.auth.enabled, false)

  workload_identity_annotations = {
    "azure.workload.identity/client-id" = local.azure.workload_identity_client_id
    "azure.workload.identity/tenant-id" = local.azure.tenant_id
  }

  ingress_service = merge(
    {
      annotations = merge(
        {
          "service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path" = "/healthz"
        },
        local.azure.load_balancer_resource_group == "" ? {} : {
          "service.beta.kubernetes.io/azure-load-balancer-resource-group" = local.azure.load_balancer_resource_group
        },
      )
    },
    local.azure.ingress_load_balancer_ip == "" ? {} : {
      loadBalancerIP = local.azure.ingress_load_balancer_ip
    },
  )

  keyvault_secret_names = concat(
    [local.azure.database_password_secret_name, local.azure.database_username_secret_name],
    local.auth_enabled ? local.auth_secret_keys : [],
  )

  keyvault_objects = join("\n", concat(
    ["array:"],
    [for name in local.keyvault_secret_names : "  - |\n    objectName: ${name}\n    objectType: secret"],
  ))

  runtime_env = [
    { name = "AZURE_REGION", value = local.azure.location },
    { name = "AZURE_LOCATION", value = local.azure.location },
    { name = "AZURE_TENANT_ID", value = local.azure.tenant_id },
    { name = "AZURE_CLIENT_ID", value = local.azure.workload_identity_client_id },
    { name = "AZURE_STORAGE_ACCOUNT_NAME", value = local.azure.storage_account_name },
    { name = "WAREHOUSE_CONTAINER_NAME", value = local.azure.warehouse_container_name },
  ]

  hub_env = [
    { name = "KV_STORE_TYPE", value = "cosmos" },
  ]

  spark_history_opts = [
    "-Dspark.hadoop.fs.azure.account.auth.type=OAuth",
    "-Dspark.hadoop.fs.azure.account.oauth.provider.type=org.apache.hadoop.fs.azurebfs.oauth2.WorkloadIdentityTokenProvider",
    "-Dspark.hadoop.fs.azure.account.oauth2.client.id=${local.azure.workload_identity_client_id}",
    "-Dspark.hadoop.fs.azure.account.oauth2.msi.tenant=${local.azure.tenant_id}",
    "-Dspark.sql.catalog.spark_catalog.jdbc.schema-version=V1",
  ]

  provider_values = {
    podLabels = {
      "azure.workload.identity/use" = "true"
    }

    secrets = {
      provider = "azure"
      parameters = {
        usePodIdentity         = "false"
        useVMManagedIdentity   = "true"
        userAssignedIdentityID = local.azure.keyvault_identity_client_id
        keyvaultName           = local.azure.keyvault_name
        tenantId               = local.azure.tenant_id
        objects                = local.keyvault_objects
      }
    }

    polaris = {
      bootstrap = {
        rbac = {
          catalog = {
            defaultBaseLocation = local.polaris_base_location
            storage = {
              type             = "AZURE"
              allowedLocations = [local.polaris_base_location]
              config = {
                tenantId = local.azure.tenant_id
              }
            }
          }
        }
      }
    }

    "ingress-nginx-ui" = {
      controller = {
        service = local.ingress_service
      }
    }
  }
}
