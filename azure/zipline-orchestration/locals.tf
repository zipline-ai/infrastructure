locals {
  cloud_args = merge({
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

  provider_context = {
    hub = {
      image          = local.hub_image
      verticle_class = local.hub_verticle_class
    }
    eval = {
      image = local.eval_image
    }
    compute = {
      object_store = {
        bucket = local.cloud_args.warehouse_container_name
        region = local.cloud_args.location
      }
      spark_event_log_dir = local.spark_event_log_dir
      service_account = {
        annotations = local.workload_identity_annotations
      }
      flink_defaults = {
        serviceAccountAnnotations = local.workload_identity_annotations
      }
      history_server_options = local.spark_history_opts
    }
    image_pull_secret = {
      name = ""
    }
    ingress = {
      class_name                  = "nginx-ui"
      tls_secret_name             = "zipline-tls-secret"
      cert_manager_cluster_issuer = "letsencrypt-prod"
      annotations                 = {}
    }
    addons = {
      install_secrets_store_csi_driver = false
    }
    secrets = {
      database_object_names = {
        username = local.cloud_args.database_username_secret_name
        password = local.cloud_args.database_password_secret_name
      }
    }
    service_account_annotations = local.workload_identity_annotations
    runtime_env                 = local.runtime_env
    hub_env                     = local.hub_env
    values                      = local.provider_values
  }

  deployment = var.orchestration.deployment

  normalized_storage_path     = trim(local.cloud_args.storage_path_prefix, "/")
  storage_path_prefix_segment = local.normalized_storage_path == "" ? "" : "${local.normalized_storage_path}/"
  abfs_base_uri               = "abfss://${local.cloud_args.warehouse_container_name}@${local.cloud_args.storage_account_name}.dfs.core.windows.net/${local.storage_path_prefix_segment}"
  spark_event_log_dir         = try(var.orchestration.compute.spark_event_log_dir, "") != "" ? var.orchestration.compute.spark_event_log_dir : "${local.abfs_base_uri}spark-events"
  polaris_base_location       = "${local.abfs_base_uri}polaris/polaris_${local.deployment.customer_name}/"
  hub_image                   = "ziplineai/hub-azure"
  eval_image                  = "ziplineai/eval-azure"
  hub_verticle_class          = "ai.chronon.hub.AzureOrchestrationVerticle,ai.chronon.hub.AzureWorkflowExecutionVerticle"
  auth_enabled                = try(var.orchestration.auth.enabled, false)

  workload_identity_annotations = {
    "azure.workload.identity/client-id" = local.cloud_args.workload_identity_client_id
    "azure.workload.identity/tenant-id" = local.cloud_args.tenant_id
  }

  ingress_service = merge(
    {
      annotations = merge(
        {
          "service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path" = "/healthz"
        },
        local.cloud_args.load_balancer_resource_group == "" ? {} : {
          "service.beta.kubernetes.io/azure-load-balancer-resource-group" = local.cloud_args.load_balancer_resource_group
        },
      )
    },
    local.cloud_args.ingress_load_balancer_ip == "" ? {} : {
      loadBalancerIP = local.cloud_args.ingress_load_balancer_ip
    },
  )

  keyvault_secret_names = concat(
    [local.cloud_args.database_password_secret_name, local.cloud_args.database_username_secret_name],
    local.auth_enabled ? local.auth_secret_keys : [],
  )

  keyvault_objects = join("\n", concat(
    ["array:"],
    [for name in local.keyvault_secret_names : "  - |\n    objectName: ${name}\n    objectType: secret"],
  ))

  runtime_env = [
    { name = "AZURE_REGION", value = local.cloud_args.location },
    { name = "AZURE_LOCATION", value = local.cloud_args.location },
    { name = "AZURE_TENANT_ID", value = local.cloud_args.tenant_id },
    { name = "AZURE_CLIENT_ID", value = local.cloud_args.workload_identity_client_id },
    { name = "AZURE_STORAGE_ACCOUNT_NAME", value = local.cloud_args.storage_account_name },
    { name = "WAREHOUSE_CONTAINER_NAME", value = local.cloud_args.warehouse_container_name },
  ]

  hub_env = [
    { name = "KV_STORE_TYPE", value = "cosmos" },
  ]

  spark_history_opts = [
    "-Dspark.hadoop.fs.azure.account.auth.type=OAuth",
    "-Dspark.hadoop.fs.azure.account.oauth.provider.type=org.apache.hadoop.fs.azurebfs.oauth2.WorkloadIdentityTokenProvider",
    "-Dspark.hadoop.fs.azure.account.oauth2.client.id=${local.cloud_args.workload_identity_client_id}",
    "-Dspark.hadoop.fs.azure.account.oauth2.msi.tenant=${local.cloud_args.tenant_id}",
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
        userAssignedIdentityID = local.cloud_args.keyvault_identity_client_id
        keyvaultName           = local.cloud_args.keyvault_name
        tenantId               = local.cloud_args.tenant_id
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
                tenantId = local.cloud_args.tenant_id
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
