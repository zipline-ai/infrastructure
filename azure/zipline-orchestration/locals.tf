locals {
  image_pull_secret_name       = var.create_image_pull_secret ? kubernetes_secret_v1.docker_hub_creds[0].metadata[0].name : var.image_pull_secret_name
  compute_workload_identity_id = var.compute_workload_identity_client_id != "" ? var.compute_workload_identity_client_id : var.workload_identity_client_id
  normalized_storage_path      = trim(var.storage_path_prefix, "/")
  storage_path_prefix_segment  = local.normalized_storage_path == "" ? "" : "${local.normalized_storage_path}/"
  abfs_base_uri                = "abfss://${var.warehouse_container_name}@${var.azure_storage_account_name}.dfs.core.windows.net/${local.storage_path_prefix_segment}"
  spark_event_log_dir          = var.spark_event_log_dir != "" ? var.spark_event_log_dir : "${local.abfs_base_uri}spark-events"
  warehouse_prefix             = var.warehouse_prefix != "" ? var.warehouse_prefix : "${local.abfs_base_uri}warehouse"
  flink_state_uri              = var.flink_state_uri != "" ? var.flink_state_uri : "${local.abfs_base_uri}flink-state"
  polaris_base_location        = "${local.abfs_base_uri}polaris/polaris_${var.customer_name}/"
  image_pull_secrets           = local.image_pull_secret_name == "" ? [] : [{ name = local.image_pull_secret_name }]
  database_host_with_port      = "${var.database_host}:${var.database_port}"
  database_url                 = "postgres://$(DB_USERNAME)@${local.database_host_with_port}/${var.database_name}?sslmode=${var.database_ssl_mode}"

  azure_spark_history_extra_spark_opts = [
    "-Dspark.hadoop.fs.azure.account.auth.type=OAuth",
    "-Dspark.hadoop.fs.azure.account.oauth.provider.type=org.apache.hadoop.fs.azurebfs.oauth2.WorkloadIdentityTokenProvider",
    "-Dspark.hadoop.fs.azure.account.oauth2.client.id=${var.workload_identity_client_id}",
    "-Dspark.hadoop.fs.azure.account.oauth2.msi.tenant=${var.tenant_id}",
    "-Dspark.sql.catalog.spark_catalog.jdbc.schema-version=V1",
  ]

  cert_manager_annotations = var.cert_manager_cluster_issuer == "" ? {} : {
    "cert-manager.io/cluster-issuer" = var.cert_manager_cluster_issuer
  }

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

  app_tls = var.tls_secret_name != "" ? [{
    hosts      = [var.domain]
    secretName = var.tls_secret_name
  }] : []

  auth_enabled = try(var.auth.enabled, false)

  database_secret_object = {
    secretName = "db-credentials"
    type       = "Opaque"
    data = [
      {
        objectName = var.database_password_secret_name
        key        = "password"
      },
      {
        objectName = var.database_username_secret_name
        key        = "username"
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
    var.extra_secret_objects,
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
      value = var.flink_service_account_name
    },
    {
      name  = "FLINK_AKS_NAMESPACE"
      value = var.compute_default_namespace
    },
  ]

  values = {
    global = {
      customer_name   = var.customer_name
      artifact_prefix = var.artifact_prefix
      version         = var.zipline_version
      deploy_fetcher  = var.deploy_fetcher
      cloud_provider  = "azure"
    }

    runtime = {
      env = concat(local.azure_runtime_env, var.runtime_env)
    }

    serviceAccount = {
      create      = true
      name        = "orchestration-sa"
      annotations = local.orchestration_service_account_annotations
    }

    podLabels = local.pod_labels

    imagePullSecrets = local.image_pull_secrets

    database = {
      url     = local.database_url
      host    = var.database_host
      port    = var.database_port
      name    = var.database_name
      sslMode = var.database_ssl_mode
      credentialsSecret = {
        name        = var.database_credentials_secret_name
        usernameKey = var.database_username_secret_key
        passwordKey = var.database_password_secret_key
      }
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
      enabled          = true
      defaultNamespace = var.compute_default_namespace
      namespaces       = var.compute_namespaces
      objectStore = {
        bucket = var.warehouse_container_name
        region = var.location
      }
      serviceAccount = {
        sparkName   = var.spark_service_account_name
        flinkName   = var.flink_service_account_name
        annotations = local.compute_service_account_annotations
      }
      rbac = {
        create = var.compute_rbac_create
      }
      sparkDefaults = {
        eventLogDir = local.spark_event_log_dir
        image       = var.spark_image
      }
      historyServer = {
        extraSparkHistoryOpts = concat(local.azure_spark_history_extra_spark_opts, var.spark_history_extra_spark_opts)
      }
      flinkDefaults = {
        image                     = var.flink_image
        serviceAccount            = var.flink_service_account_name
        serviceAccountAnnotations = local.compute_service_account_annotations
      }
      imagePrepull = {
        enabled = var.compute_image_prepull_enabled
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
        image         = var.hub_image
        verticleClass = var.hub_verticle_class
        env           = concat(local.azure_hub_env, var.hub_env)
      }
      fetcher = {
        replicas = var.fetcher_replicas
      }
      eval = {
        image = var.eval_image
      }
    }

    ingress = {
      ui = {
        className = var.ingress_class_name
        host      = var.domain
        tls       = local.app_tls
        annotations = merge(
          local.cert_manager_annotations,
          var.ingress_annotations,
          var.ui_ingress_annotations,
        )
      }
      hub = {
        className = var.ingress_class_name
        host      = var.domain
        tls       = local.app_tls
        annotations = merge(
          local.cert_manager_annotations,
          var.ingress_annotations,
          var.hub_ingress_annotations,
        )
      }
      fetcher = {
        className = var.ingress_class_name
        host      = var.domain
        tls       = local.app_tls
        annotations = merge(
          local.cert_manager_annotations,
          var.ingress_annotations,
          var.fetcher_ingress_annotations,
        )
      }
      eval = {
        className = var.ingress_class_name
        host      = var.domain
        tls       = local.app_tls
        annotations = merge(
          local.cert_manager_annotations,
          var.ingress_annotations,
          var.eval_ingress_annotations,
        )
      }
      polaris = {
        className = var.ingress_class_name
      }
    }

    "ingress-nginx-ui" = {
      controller = {
        service = local.ingress_service
      }
    }

    prometheus = {
      queryEndpoint = var.prometheus_query_endpoint
      namespace     = var.namespace
    }

    auth = var.auth
  }
}
