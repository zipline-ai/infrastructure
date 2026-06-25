locals {
  azure = merge({
    database_password_secret_name = "pg-admin-password"
    database_username_secret_name = "pg-admin-username"
    storage_path_prefix           = ""
    ingress_load_balancer_ip      = ""
    load_balancer_resource_group  = ""
    crucible_jar_uri              = ""
  }, var.azure)

  auth_secret_keys = [
    "auth-secret",
    "google-oauth-client-secret",
    "github-oauth-client-secret",
    "microsoft-entra-oauth-client-secret",
    "sso-client-secret",
  ]

  orchestration = merge(var.orchestration, {
    image_pull_secret = merge({
      name = ""
    }, try(var.orchestration.image_pull_secret, {}))
    database = merge({
      ssl_mode = "require"
    }, var.orchestration.database)
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
      enabled = true
      database_object_names = merge({
        username = local.azure.database_username_secret_name
        password = local.azure.database_password_secret_name
      }, try(var.orchestration.secrets.database_object_names, {}))
    })
    provider_service_account_annotations = local.workload_identity_annotations
    provider_runtime_env                 = local.runtime_env
    provider_hub_env                     = local.hub_env
  })

  deployment = local.orchestration.deployment
  database   = local.orchestration.database
  compute    = merge({ spark_event_log_dir = "", flink_service_account = "flink", default_namespace = "zipline-default" }, try(local.orchestration.compute, {}))

  normalized_storage_path     = trim(local.azure.storage_path_prefix, "/")
  storage_path_prefix_segment = local.normalized_storage_path == "" ? "" : "${local.normalized_storage_path}/"
  abfs_base_uri               = "abfss://${local.azure.warehouse_container_name}@${local.azure.storage_account_name}.dfs.core.windows.net/${local.storage_path_prefix_segment}"
  spark_event_log_dir         = local.compute.spark_event_log_dir != "" ? local.compute.spark_event_log_dir : "${local.abfs_base_uri}spark-events"
  warehouse_prefix            = "${local.abfs_base_uri}warehouse"
  flink_state_uri             = "${local.abfs_base_uri}flink-state"
  polaris_base_location       = "${local.abfs_base_uri}polaris/polaris_${local.deployment.customer_name}/"
  database_host_with_port     = "${local.database.host}:${try(local.database.port, 5432)}"
  database_url                = try(local.database.url, "") != "" ? local.database.url : "postgres://$(DB_USERNAME)@${local.database_host_with_port}/${try(local.database.name, "execution_info")}?sslmode=${local.database.ssl_mode}"
  hub_image                   = "ziplineai/hub-azure"
  eval_image                  = "ziplineai/eval-azure"
  hub_verticle_class          = "ai.chronon.hub.AzureCrucibleOrchestrationVerticle,ai.chronon.hub.AzureCrucibleWorkflowExecutionVerticle"
  auth_enabled                = try(local.orchestration.auth.enabled, false)

  workload_identity_annotations = {
    "azure.workload.identity/client-id" = local.azure.workload_identity_client_id
    "azure.workload.identity/tenant-id" = local.azure.tenant_id
  }

  compute_service_account_annotations = {
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
    { name = "WAREHOUSE_PREFIX", value = local.warehouse_prefix },
    { name = "FLINK_STATE_URI", value = local.flink_state_uri },
    { name = "CHRONON_ONLINE_CLASS", value = "ai.chronon.integrations.cloud_azure.AzureApiImpl" },
    { name = "CRUCIBLE_JAR_NAME", value = "cloud_azure_lib_deploy.jar" },
    { name = "CRUCIBLE_JAR_URI", value = local.azure.crucible_jar_uri },
    { name = "CRUCIBLE_SPOT_EXECUTORS", value = "true" },
    { name = "FLINK_AKS_SERVICE_ACCOUNT", value = try(var.orchestration.compute.flink_service_account, "flink") },
    { name = "FLINK_AKS_NAMESPACE", value = try(var.orchestration.compute.default_namespace, "zipline-default") },
  ]

  spark_history_opts = [
    "-Dspark.hadoop.fs.azure.account.auth.type=OAuth",
    "-Dspark.hadoop.fs.azure.account.oauth.provider.type=org.apache.hadoop.fs.azurebfs.oauth2.WorkloadIdentityTokenProvider",
    "-Dspark.hadoop.fs.azure.account.oauth2.client.id=${local.azure.workload_identity_client_id}",
    "-Dspark.hadoop.fs.azure.account.oauth2.msi.tenant=${local.azure.tenant_id}",
    "-Dspark.sql.catalog.spark_catalog.jdbc.schema-version=V1",
  ]

  provider_values = {
    global = {
      cloud_provider = "azure"
    }

    podLabels = {
      "azure.workload.identity/use" = "true"
    }

    database = {
      url = local.database_url
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

    compute = {
      objectStore = {
        bucket = local.azure.warehouse_container_name
        region = local.azure.location
      }
      serviceAccount = {
        annotations = local.compute_service_account_annotations
      }
      sparkDefaults = {
        eventLogDir = local.spark_event_log_dir
      }
      historyServer = {
        extraSparkHistoryOpts = concat(local.spark_history_opts, try(local.compute.history_server_options, []))
      }
      flinkDefaults = {
        serviceAccountAnnotations = local.compute_service_account_annotations
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

    orchestration = {
      hub = {
        image         = local.hub_image
        verticleClass = local.hub_verticle_class
      }
      eval = {
        image = local.eval_image
      }
    }

    "ingress-nginx-ui" = {
      controller = {
        service = local.ingress_service
      }
    }
  }
}
