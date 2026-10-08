locals {
  cloud_args = merge({
    subscription_id                         = ""
    resource_group_name                     = ""
    cluster_name                            = ""
    kubernetes_version                      = "1.36.1"
    aks_dns_prefix                          = ""
    vnet_address_space                      = ["10.0.0.0/16"]
    aks_subnet_address_prefixes             = ["10.0.0.0/22"]
    private_endpoints_subnet_address_prefix = "10.0.5.0/24"
    aks_service_cidr                        = "172.20.0.0/16"
    aks_dns_service_ip                      = "172.20.0.10"
    aks_pod_cidr                            = "10.244.0.0/16"
    default_node_pool                       = {}
    node_pools                              = {}
    existing_keyvault_id                   = ""
    keyvault_name                           = ""
    admin_principal_names                   = []
    workload_identity_name                  = ""
    workload_identity_client_id             = ""
    storage_account_resource_group          = ""
    storage_role_definition_names           = ["Storage Blob Data Contributor"]
    resource_group_role_definition_names    = []
    container_registry_name                 = ""
    container_registry_resource_group       = ""
    database_host                           = ""
    database_location                       = ""
    database_name                           = ""
    database_port                           = 5432
    database_server_name                    = ""
    database_credentials_secret_name        = ""
    database_admin_username                 = "locker_user"
    database_password_secret_name           = "pg-admin-password"
    database_username_secret_name           = "pg-admin-username"
    database_version                        = "16"
    database_sku_name                       = "B_Standard_B1ms"
    database_storage_mb                     = 32768
    database_backup_retention_days          = 7
    database_public_network_access_enabled  = false
    logs_container_name                     = ""
    storage_path_prefix                     = ""
    ingress_load_balancer_ip                = ""
    load_balancer_resource_group            = ""
    monitor_workspace_name                  = ""
    monitor_workspace_public_network_access = true
    monitor_metrics_annotations_allowed     = null
    monitor_metrics_labels_allowed          = null
    fetcher_cosmos_account_name             = ""
    fetcher_cosmos_database                 = "chronon"
    fetcher_cosmos_preferred_regions        = []
    fetcher_cosmos_secret_name              = "secretcosmos-primary-key"
    fetcher_cosmos_secret_key               = "COSMOS_KEY"
  }, var.azure)

  deployment                       = var.orchestration.deployment
  deploy_fetcher                   = try(local.deployment.deploy_fetcher, false)
  name_prefix                      = local.deployment.customer_name
  resource_group_name              = local.cloud_args.resource_group_name != "" ? local.cloud_args.resource_group_name : "${local.name_prefix}-crucible-rg"
  cluster_name                     = local.cloud_args.cluster_name != "" ? local.cloud_args.cluster_name : "${local.name_prefix}-aks"
  aks_dns_prefix                   = local.cloud_args.aks_dns_prefix != "" ? local.cloud_args.aks_dns_prefix : local.cluster_name
  use_existing_keyvault            = trimspace(local.cloud_args.existing_keyvault_id) != ""
  created_keyvault_name            = local.cloud_args.keyvault_name != "" ? local.cloud_args.keyvault_name : "${local.name_prefix}-zipline-secrets"
  keyvault_name                    = local.use_existing_keyvault ? element(reverse(split("/", trimsuffix(local.cloud_args.existing_keyvault_id, "/"))), 0) : local.created_keyvault_name
  keyvault_id                      = local.use_existing_keyvault ? trimsuffix(local.cloud_args.existing_keyvault_id, "/") : azurerm_key_vault.main[0].id
  workload_identity_name           = local.cloud_args.workload_identity_name != "" ? local.cloud_args.workload_identity_name : "${local.name_prefix}-workload-identity"
  storage_account_resource_group   = local.cloud_args.storage_account_resource_group != "" ? local.cloud_args.storage_account_resource_group : local.resource_group_name
  database_name                    = local.cloud_args.database_name != "" ? local.cloud_args.database_name : try(var.orchestration.database.name, "execution_info")
  database_server_name             = local.cloud_args.database_server_name != "" ? local.cloud_args.database_server_name : "${local.name_prefix}-zipline-orch-instance"
  database_credentials_secret_name = local.cloud_args.database_credentials_secret_name != "" ? local.cloud_args.database_credentials_secret_name : "${local.name_prefix}-postgres-credentials"
  database_host                    = local.cloud_args.database_host != "" ? local.cloud_args.database_host : azurerm_postgresql_flexible_server.main.fqdn
  database_location                = local.cloud_args.database_location != "" ? local.cloud_args.database_location : local.cloud_args.location
  tenant_id                        = local.cloud_args.tenant_id != "" ? local.cloud_args.tenant_id : data.azurerm_client_config.current.tenant_id
  workload_identity_client_id      = local.cloud_args.workload_identity_client_id != "" ? local.cloud_args.workload_identity_client_id : azurerm_user_assigned_identity.workload.client_id
  load_balancer_resource_group     = local.cloud_args.load_balancer_resource_group != "" ? local.cloud_args.load_balancer_resource_group : azurerm_kubernetes_cluster.main.node_resource_group
  monitor_workspace_name           = local.cloud_args.monitor_workspace_name != "" ? local.cloud_args.monitor_workspace_name : "${local.name_prefix}-prometheus"

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
    database = {
      host = local.database_host
      port = local.cloud_args.database_port
      name = local.database_name
      credentials_secret = {
        name         = local.database_credentials_secret_name
        username_key = local.cloud_args.database_username_secret_name
        password_key = local.cloud_args.database_password_secret_name
      }
    }
    hub = {
      image          = local.hub_image
      verticle_class = local.hub_verticle_class
      pod_annotations = merge(
        local.hub_prometheus_pod_annotations,
        try(var.orchestration.hub.podAnnotations, {}),
        try(var.orchestration.hub.pod_annotations, {}),
      )
    }
    eval = {
      image = local.eval_image
    }
    prometheus = {
      query_endpoint = azurerm_monitor_workspace.prometheus.query_endpoint
    }
    metrics_provider = "azure"
    addons = {
      install_metrics_server = try(var.orchestration.addons.install_metrics_server, false)
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
      history_server_options = local.spark_history_opts
    }
    ingress = {
      class_name                  = "nginx-ui"
      tls_secret_name             = "zipline-tls-secret"
      cert_manager_cluster_issuer = "letsencrypt-prod"
    }
    secrets = {
      secret_store = {
        create = true
        name   = "zipline-secret-store"
        kind   = "SecretStore"
        spec = {
          provider = {
            azurekv = {
              authType = "WorkloadIdentity"
              vaultUrl = "https://${local.keyvault_name}.vault.azure.net"
              serviceAccountRef = {
                name = local.orchestration_service_account
              }
            }
          }
        }
      }
      database_remote_refs = {
        username = {
          key = local.cloud_args.database_username_secret_name
        }
        password = {
          key = local.cloud_args.database_password_secret_name
        }
      }
      auth_remote_refs = {
        for key in local.auth_secret_keys : key => {
          key = key
        }
      }
      extra_external_secrets = local.deploy_fetcher ? [
        {
          name = local.cloud_args.fetcher_cosmos_secret_name
          spec = {
            refreshInterval = "1h"
            secretStoreRef = {
              name = try(var.orchestration.secrets.secret_store.name, "zipline-secret-store")
              kind = "SecretStore"
            }
            target = {
              name           = local.cloud_args.fetcher_cosmos_secret_name
              creationPolicy = "Owner"
              template = {
                type = "Opaque"
              }
            }
            data = [
              {
                secretKey = local.cloud_args.fetcher_cosmos_secret_key
                remoteRef = {
                  key = azurerm_key_vault_secret.fetcher_cosmos_key[0].name
                }
              }
            ]
          }
        }
      ] : []
    }
    service_account_annotations = local.workload_identity_annotations
    runtime_env = [
      { name = "AZURE_REGION", value = local.cloud_args.location },
      { name = "AZURE_TENANT_ID", value = local.tenant_id },
      { name = "AZURE_CLIENT_ID", value = local.workload_identity_client_id },
      { name = "AZURE_STORAGE_ACCOUNT_NAME", value = local.cloud_args.storage_account_name },
    ]
    fetcher_env = [
      { name = "PROVIDER", value = "AZURE" },
      { name = "KV_STORE_TYPE", value = "cosmos" },
      { name = "COSMOS_ENDPOINT", value = local.deploy_fetcher ? azurerm_cosmosdb_account.fetcher[0].endpoint : "" },
      { name = "COSMOS_DATABASE", value = local.cloud_args.fetcher_cosmos_database },
      {
        name  = "COSMOS_PREFERRED_REGIONS"
        value = join(",", length(local.cloud_args.fetcher_cosmos_preferred_regions) > 0 ? local.cloud_args.fetcher_cosmos_preferred_regions : [local.cloud_args.location])
      },
      {
        name = "COSMOS_KEY"
        valueFrom = {
          secretKeyRef = {
            name = local.cloud_args.fetcher_cosmos_secret_name
            key  = local.cloud_args.fetcher_cosmos_secret_key
          }
        }
      },
    ]
    values = local.provider_values
  }

  normalized_storage_path     = trim(local.cloud_args.storage_path_prefix, "/")
  storage_path_prefix_segment = local.normalized_storage_path == "" ? "" : "${local.normalized_storage_path}/"
  abfs_base_uri               = "abfss://${local.cloud_args.warehouse_container_name}@${local.cloud_args.storage_account_name}.dfs.core.windows.net/${local.storage_path_prefix_segment}"
  spark_event_log_uri_prefix  = "abfss://${local.cloud_args.warehouse_container_name}@${local.cloud_args.storage_account_name}.dfs.core.windows.net/"
  spark_event_log_dir         = try(var.orchestration.compute.spark_event_log_dir, "") != "" ? var.orchestration.compute.spark_event_log_dir : "${local.spark_event_log_uri_prefix}spark-events"
  spark_event_log_managed     = startswith(local.spark_event_log_dir, local.spark_event_log_uri_prefix)
  spark_event_log_path        = trim(trimprefix(local.spark_event_log_dir, local.spark_event_log_uri_prefix), "/")
  polaris_base_location       = "${local.abfs_base_uri}polaris/polaris_${local.deployment.customer_name}/"
  hub_image                   = "ziplineai/hub-azure"
  eval_image                  = "ziplineai/eval-azure"
  hub_verticle_class          = "ai.chronon.hub.AzureOrchestrationVerticle,ai.chronon.hub.AzureWorkflowExecutionVerticle,ai.chronon.hub.cleanup.AzureCleanupVerticle"
  hub_metrics_reader          = try(var.orchestration.hub.chronon_metrics_reader, try(var.orchestration.hub.metricsReader, "prometheus"))
  hub_metrics_port            = try(var.orchestration.hub.metrics_port, try(var.orchestration.hub.metricsPort, 8905))
  hub_prometheus_pod_annotations = local.hub_metrics_reader == "prometheus" ? {
    "prometheus.io/scrape" = "true"
    "prometheus.io/port"   = tostring(local.hub_metrics_port)
    "prometheus.io/path"   = "/metrics"
  } : {}
  auth_enabled             = try(var.orchestration.auth.enabled, false)
  artifact_prefix_location = trimprefix(trimprefix(trimspace(local.deployment.artifact_prefix), "abfss://"), "wasbs://")
  artifact_container_name  = split("@", local.artifact_prefix_location)[0]
  logs_container_name      = local.cloud_args.logs_container_name != "" ? local.cloud_args.logs_container_name : "zipline-logs-${local.deployment.customer_name}"

  storage_container_names = toset(distinct(compact([
    local.artifact_container_name,
    local.cloud_args.warehouse_container_name,
    local.logs_container_name,
  ])))

  workload_identity_annotations = {
    "azure.workload.identity/client-id" = local.workload_identity_client_id
    "azure.workload.identity/tenant-id" = local.tenant_id
  }

  ingress_service = merge(
    {
      enabled = true
      external = {
        enabled = true
      }
      type = "LoadBalancer"
      annotations = merge(
        {
          "service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path" = "/healthz"
        },
        local.load_balancer_resource_group == "" ? {} : {
          "service.beta.kubernetes.io/azure-load-balancer-resource-group" = local.load_balancer_resource_group
        },
      )
    },
    local.cloud_args.ingress_load_balancer_ip == "" ? {} : {
      loadBalancerIP = local.cloud_args.ingress_load_balancer_ip
    },
  )

  spark_history_opts = [
    "-Dspark.hadoop.fs.azure.account.auth.type=OAuth",
    "-Dspark.hadoop.fs.azure.account.oauth.provider.type=org.apache.hadoop.fs.azurebfs.oauth2.WorkloadIdentityTokenProvider",
    "-Dspark.hadoop.fs.azure.account.oauth2.client.id=${local.workload_identity_client_id}",
    "-Dspark.hadoop.fs.azure.account.oauth2.msi.tenant=${local.tenant_id}",
    "-Dspark.sql.catalog.spark_catalog.jdbc.schema-version=V1",
  ]

  provider_values = {
    podLabels = {
      "azure.workload.identity/use" = "true"
    }

    starrocks = {
      feConfig = {
        run_mode                                = "shared_data"
        cloud_native_storage_type               = "ADLS2"
        azure_adls2_path                        = "${local.cloud_args.warehouse_container_name}/dataexplorer"
        azure_adls2_endpoint                    = "https://${local.cloud_args.storage_account_name}.dfs.core.windows.net"
        azure_adls2_oauth2_use_managed_identity = true
        azure_adls2_oauth2_client_id            = local.workload_identity_client_id
        azure_adls2_oauth2_tenant_id            = local.tenant_id
        enable_load_volume_from_conf            = true
      }
      serviceAccount = local.orchestration_service_account
      podLabels = {
        "azure.workload.identity/use" = "true"
      }
    }

    polaris = {
      extraEnv = [
        { name = "AZURE_REGION", value = local.cloud_args.location },
        { name = "AZURE_TENANT_ID", value = local.tenant_id },
        { name = "AZURE_CLIENT_ID", value = local.workload_identity_client_id },
        { name = "AZURE_STORAGE_ACCOUNT_NAME", value = local.cloud_args.storage_account_name },
      ]
      bootstrap = {
        rbac = {
          catalog = {
            defaultBaseLocation = local.polaris_base_location
            storage = {
              type             = "AZURE"
              allowedLocations = [local.polaris_base_location]
              config = {
                tenantId     = local.tenant_id
                hierarchical = true
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
