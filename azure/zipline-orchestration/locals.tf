locals {
  orchestration = merge(var.orchestration, {
    install = merge({
      release_name = "zipline-orchestration"
      namespace    = "zipline-system"
      helm_wait    = true
      helm_timeout = 300
    }, try(var.orchestration.install, {}))
    image_pull_secret = merge({
      name               = ""
      create             = false
      dockerhub_username = "ziplineai"
      dockerhub_token    = ""
    }, try(var.orchestration.image_pull_secret, {}))
    database = merge({
      port               = 5432
      name               = "execution_info"
      ssl_mode           = "require"
      jdbc_url           = ""
      url                = ""
      credentials_secret = {}
    }, var.orchestration.database)
    ingress = merge({
      class_name                  = "nginx-ui"
      tls_secret_name             = "zipline-tls-secret"
      cert_manager_cluster_issuer = "letsencrypt-prod"
      annotations                 = {}
    }, var.orchestration.ingress)
    compute = merge({
      spark_image           = "ziplineai/spark:nightly"
      flink_image           = "ziplineai/flink:1.20.3"
      spark_service_account = "spark-operator-spark"
      flink_service_account = "flink"
      default_namespace     = "zipline-default"
      spark_event_log_dir   = ""
    }, try(var.orchestration.compute, {}))
    addons = merge({
      install_secrets_store_csi_driver = false
      install_cert_manager             = true
      install_flink_operator           = true
      install_opentelemetry_operator   = false
    }, try(var.orchestration.addons, {}))
  })

  deployment                  = local.orchestration.deployment
  database                    = local.orchestration.database
  database_credentials_secret = merge({ name = "db-credentials", username_key = "username", password_key = "password" }, try(local.database.credentials_secret, {}))
  compute                     = local.orchestration.compute
  compute_workload_identity_id = (
    var.compute_workload_identity_client_id != ""
    ? var.compute_workload_identity_client_id
    : var.workload_identity_client_id
  )
  normalized_storage_path     = trim(var.storage_path_prefix, "/")
  storage_path_prefix_segment = local.normalized_storage_path == "" ? "" : "${local.normalized_storage_path}/"
  abfs_base_uri               = "abfss://${var.warehouse_container_name}@${var.azure_storage_account_name}.dfs.core.windows.net/${local.storage_path_prefix_segment}"
  spark_event_log_dir         = local.compute.spark_event_log_dir != "" ? local.compute.spark_event_log_dir : "${local.abfs_base_uri}spark-events"
  warehouse_prefix            = var.warehouse_prefix != "" ? var.warehouse_prefix : "${local.abfs_base_uri}warehouse"
  flink_state_uri             = var.flink_state_uri != "" ? var.flink_state_uri : "${local.abfs_base_uri}flink-state"
  polaris_base_location       = "${local.abfs_base_uri}polaris/polaris_${local.deployment.customer_name}/"
  database_host_with_port     = "${local.database.host}:${local.database.port}"
  database_url                = local.database.url != "" ? local.database.url : "postgres://$(DB_USERNAME)@${local.database_host_with_port}/${local.database.name}?sslmode=${local.database.ssl_mode}"
  hub_image                   = "ziplineai/hub-azure"
  eval_image                  = "ziplineai/eval-azure"
  hub_verticle_class          = "ai.chronon.hub.AzureCrucibleOrchestrationVerticle,ai.chronon.hub.AzureCrucibleWorkflowExecutionVerticle"

  auth_enabled = try(local.orchestration.auth.enabled, false)

  azure_spark_history_extra_spark_opts = [
    "-Dspark.hadoop.fs.azure.account.auth.type=OAuth",
    "-Dspark.hadoop.fs.azure.account.oauth.provider.type=org.apache.hadoop.fs.azurebfs.oauth2.WorkloadIdentityTokenProvider",
    "-Dspark.hadoop.fs.azure.account.oauth2.client.id=${var.workload_identity_client_id}",
    "-Dspark.hadoop.fs.azure.account.oauth2.msi.tenant=${var.tenant_id}",
    "-Dspark.sql.catalog.spark_catalog.jdbc.schema-version=V1",
  ]

  orchestration_service_account_annotations = {
    "azure.workload.identity/client-id" = var.workload_identity_client_id
    "azure.workload.identity/tenant-id" = var.tenant_id
  }

  compute_service_account_annotations = {
    "azure.workload.identity/client-id" = local.compute_workload_identity_id
    "azure.workload.identity/tenant-id" = var.tenant_id
  }

  pod_labels = {
    "azure.workload.identity/use" = "true"
  }

  azure_lb_annotations = merge(
    {
      "service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path" = "/healthz"
    },
    var.load_balancer_resource_group == "" ? {} : {
      "service.beta.kubernetes.io/azure-load-balancer-resource-group" = var.load_balancer_resource_group
    },
    var.ingress_service_annotations,
  )

  ingress_service = merge(
    {
      annotations = local.azure_lb_annotations
    },
    var.ingress_load_balancer_ip == "" ? {} : {
      loadBalancerIP = var.ingress_load_balancer_ip
    },
  )

  database_secret_object = {
    secretName = local.database_credentials_secret.name
    type       = "Opaque"
    data = [
      {
        objectName = var.database_password_secret_name
        key        = local.database_credentials_secret.password_key
      },
      {
        objectName = var.database_username_secret_name
        key        = local.database_credentials_secret.username_key
      },
    ]
  }

  auth_secret_objects = local.auth_enabled ? [
    {
      secretName = "auth-secret"
      type       = "Opaque"
      data = [
        {
          objectName = "auth-secret"
          key        = "auth-secret"
        },
        {
          objectName = "google-oauth-client-secret"
          key        = "google-oauth-client-secret"
        },
        {
          objectName = "github-oauth-client-secret"
          key        = "github-oauth-client-secret"
        },
        {
          objectName = "microsoft-entra-oauth-client-secret"
          key        = "microsoft-entra-oauth-client-secret"
        },
        {
          objectName = "sso-client-secret"
          key        = "sso-client-secret"
        },
      ]
    }
  ] : []

  secret_objects = concat(
    [local.database_secret_object],
    local.auth_secret_objects,
    try(local.orchestration.extra_secret_objects, []),
  )

  keyvault_secret_names = concat(
    [
      var.database_password_secret_name,
      var.database_username_secret_name,
    ],
    local.auth_enabled ? [
      "auth-secret",
      "google-oauth-client-secret",
      "github-oauth-client-secret",
      "microsoft-entra-oauth-client-secret",
      "sso-client-secret",
    ] : [],
    var.extra_keyvault_secret_names,
  )

  keyvault_objects = join("\n", concat(
    ["array:"],
    [for name in local.keyvault_secret_names : "  - |\n    objectName: ${name}\n    objectType: secret"],
  ))

  azure_runtime_env = [
    {
      name  = "AZURE_REGION"
      value = var.location
    },
    {
      name  = "AZURE_LOCATION"
      value = var.location
    },
    {
      name  = "AZURE_TENANT_ID"
      value = var.tenant_id
    },
    {
      name  = "AZURE_CLIENT_ID"
      value = var.workload_identity_client_id
    },
    {
      name  = "AZURE_STORAGE_ACCOUNT_NAME"
      value = var.azure_storage_account_name
    },
    {
      name  = "WAREHOUSE_CONTAINER_NAME"
      value = var.warehouse_container_name
    },
  ]

  azure_hub_env = [
    {
      name  = "KV_STORE_TYPE"
      value = var.kv_store_type
    },
    {
      name  = "TABLE_PARTITIONS_DATASET"
      value = var.table_partitions_dataset
    },
    {
      name  = "DATA_QUALITY_METRICS_DATASET"
      value = var.data_quality_metrics_dataset
    },
    {
      name  = "WAREHOUSE_PREFIX"
      value = local.warehouse_prefix
    },
    {
      name  = "FLINK_STATE_URI"
      value = local.flink_state_uri
    },
    {
      name  = "CHRONON_ONLINE_CLASS"
      value = var.chronon_online_class
    },
    {
      name  = "CRUCIBLE_JAR_NAME"
      value = var.crucible_jar_name
    },
    {
      name  = "CRUCIBLE_JAR_URI"
      value = var.crucible_jar_uri
    },
    {
      name  = "CRUCIBLE_SPOT_EXECUTORS"
      value = tostring(var.crucible_spot_executors)
    },
    {
      name  = "FLINK_AKS_SERVICE_ACCOUNT"
      value = local.compute.flink_service_account
    },
    {
      name  = "FLINK_AKS_NAMESPACE"
      value = local.compute.default_namespace
    },
  ]

  provider_values = {
    global = {
      cloud_provider = "azure"
    }

    runtime = {
      env = concat(local.azure_runtime_env, try(local.orchestration.runtime_env, []))
    }

    serviceAccount = {
      create      = true
      name        = "orchestration-sa"
      annotations = local.orchestration_service_account_annotations
    }

    podLabels = local.pod_labels

    database = {
      url = local.database_url
    }

    secrets = {
      enabled       = var.secrets_enabled
      provider      = "azure"
      className     = "zipline-secret-provider"
      secretObjects = local.secret_objects
      parameters = {
        usePodIdentity         = "false"
        useVMManagedIdentity   = "true"
        userAssignedIdentityID = var.keyvault_identity_client_id
        keyvaultName           = var.keyvault_name
        tenantId               = var.tenant_id
        objects                = local.keyvault_objects
      }
    }

    compute = {
      objectStore = {
        bucket = var.warehouse_container_name
        region = var.location
      }
      serviceAccount = {
        annotations = local.compute_service_account_annotations
      }
      sparkDefaults = {
        eventLogDir = local.spark_event_log_dir
      }
      historyServer = {
        extraSparkHistoryOpts = concat(local.azure_spark_history_extra_spark_opts, try(local.compute.history_server_options, []))
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
                tenantId = var.tenant_id
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
        env           = concat(local.azure_hub_env, try(local.orchestration.hub_env, []))
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
