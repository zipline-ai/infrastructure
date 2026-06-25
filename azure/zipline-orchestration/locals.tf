locals {
  azure = merge({
    compute_workload_identity_client_id = ""
    secrets_enabled                     = true
    database_password_secret_name       = "pg-admin-password"
    database_username_secret_name       = "pg-admin-username"
    storage_path_prefix                 = ""
    ingress_load_balancer_ip            = ""
    load_balancer_resource_group        = ""
    warehouse_prefix                    = ""
    flink_state_uri                     = ""
    kv_store_type                       = "cosmos"
    chronon_online_class                = "ai.chronon.integrations.cloud_azure.AzureApiImpl"
    crucible_jar_name                   = "cloud_azure_lib_deploy.jar"
    crucible_jar_uri                    = ""
    crucible_spot_executors             = true
    ingress_service_annotations         = {}
    extra_keyvault_secret_names         = []
  }, var.azure)

  auth_secret_keys = [
    "auth-secret",
    "google-oauth-client-secret",
    "github-oauth-client-secret",
    "microsoft-entra-oauth-client-secret",
    "sso-client-secret",
  ]

  compute_input = try(var.orchestration.compute, {})

  orchestration = merge(var.orchestration, {
    cloud_provider = "azure"
    image_pull_secret = merge({
      name = ""
    }, try(var.orchestration.image_pull_secret, {}))
    ingress = merge(
      {
        class_name                  = "nginx-ui"
        tls_secret_name             = "zipline-tls-secret"
        cert_manager_cluster_issuer = "letsencrypt-prod"
        annotations                 = {}
      },
      try(var.orchestration.ingress, {}),
      {
        service = local.ingress_service
      },
    )
    addons = merge({
      install_secrets_store_csi_driver = false
    }, try(var.orchestration.addons, {}))
    secrets = merge(try(var.orchestration.secrets, {}), {
      enabled  = local.azure.secrets_enabled
      provider = "azure"
      parameters = merge(try(var.orchestration.secrets.parameters, {}), {
        usePodIdentity         = "false"
        useVMManagedIdentity   = "true"
        userAssignedIdentityID = local.azure.keyvault_identity_client_id
        keyvaultName           = local.azure.keyvault_name
        tenantId               = local.azure.tenant_id
        objects                = local.keyvault_objects
      })
      database_object_names = merge({
        username = local.azure.database_username_secret_name
        password = local.azure.database_password_secret_name
      }, try(var.orchestration.secrets.database_object_names, {}))
    })
    compute = merge(local.compute_input, {
      object_store = merge(try(local.compute_input.object_store, {}), {
        bucket = local.azure.warehouse_container_name
        region = local.azure.location
      })
      service_account = merge(try(local.compute_input.service_account, {}), {
        annotations = merge(try(local.compute_input.service_account.annotations, {}), local.compute_service_account_annotations)
      })
      spark_event_log_dir = local.spark_event_log_dir
      history_server_options = concat(
        local.spark_history_opts,
        try(local.compute_input.history_server_options, []),
      )
      flink_defaults = merge(try(local.compute_input.flink_defaults, {}), {
        serviceAccountAnnotations = merge(
          try(local.compute_input.flink_defaults.serviceAccountAnnotations, {}),
          local.compute_service_account_annotations,
        )
      })
    })
    polaris = merge(try(var.orchestration.polaris, {}), {
      storage = merge(try(var.orchestration.polaris.storage, {}), {
        type          = "AZURE"
        base_location = local.polaris_base_location
        config = {
          tenantId = local.azure.tenant_id
        }
      })
    })
    hub = merge(try(var.orchestration.hub, {}), {
      verticle_class = local.hub_verticle_class
    })
    pod_labels = merge(try(var.orchestration.pod_labels, {}), {
      "azure.workload.identity/use" = "true"
    })
    provider_service_account_annotations = local.workload_identity_annotations
    provider_runtime_env                 = local.runtime_env
    provider_hub_env                     = local.hub_env
  })

  compute_workload_identity_id = (
    local.azure.compute_workload_identity_client_id != ""
    ? local.azure.compute_workload_identity_client_id
    : local.azure.workload_identity_client_id
  )

  normalized_storage_path     = trim(local.azure.storage_path_prefix, "/")
  storage_path_prefix_segment = local.normalized_storage_path == "" ? "" : "${local.normalized_storage_path}/"
  abfs_base_uri               = "abfss://${local.azure.warehouse_container_name}@${local.azure.storage_account_name}.dfs.core.windows.net/${local.storage_path_prefix_segment}"
  spark_event_log_dir         = try(local.compute_input.spark_event_log_dir, "") != "" ? local.compute_input.spark_event_log_dir : "${local.abfs_base_uri}spark-events"
  warehouse_prefix            = local.azure.warehouse_prefix != "" ? local.azure.warehouse_prefix : "${local.abfs_base_uri}warehouse"
  flink_state_uri             = local.azure.flink_state_uri != "" ? local.azure.flink_state_uri : "${local.abfs_base_uri}flink-state"
  polaris_base_location       = "${local.abfs_base_uri}polaris/polaris_${var.orchestration.deployment.customer_name}/"
  hub_verticle_class          = "ai.chronon.hub.AzureCrucibleOrchestrationVerticle,ai.chronon.hub.AzureCrucibleWorkflowExecutionVerticle"
  auth_enabled                = try(var.orchestration.auth.enabled, false)

  workload_identity_annotations = {
    "azure.workload.identity/client-id" = local.azure.workload_identity_client_id
    "azure.workload.identity/tenant-id" = local.azure.tenant_id
  }

  compute_service_account_annotations = {
    "azure.workload.identity/client-id" = local.compute_workload_identity_id
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
        local.azure.ingress_service_annotations,
      )
    },
    local.azure.ingress_load_balancer_ip == "" ? {} : {
      loadBalancerIP = local.azure.ingress_load_balancer_ip
    },
  )

  keyvault_secret_names = concat(
    [local.azure.database_password_secret_name, local.azure.database_username_secret_name],
    local.auth_enabled ? local.auth_secret_keys : [],
    local.azure.extra_keyvault_secret_names,
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
    { name = "KV_STORE_TYPE", value = local.azure.kv_store_type },
    { name = "WAREHOUSE_PREFIX", value = local.warehouse_prefix },
    { name = "FLINK_STATE_URI", value = local.flink_state_uri },
    { name = "CHRONON_ONLINE_CLASS", value = local.azure.chronon_online_class },
    { name = "CRUCIBLE_JAR_NAME", value = local.azure.crucible_jar_name },
    { name = "CRUCIBLE_JAR_URI", value = local.azure.crucible_jar_uri },
    { name = "CRUCIBLE_SPOT_EXECUTORS", value = tostring(local.azure.crucible_spot_executors) },
    { name = "FLINK_AKS_SERVICE_ACCOUNT", value = try(local.compute_input.flink_service_account, "flink") },
    { name = "FLINK_AKS_NAMESPACE", value = try(local.compute_input.default_namespace, "zipline-default") },
  ]

  spark_history_opts = [
    "-Dspark.hadoop.fs.azure.account.auth.type=OAuth",
    "-Dspark.hadoop.fs.azure.account.oauth.provider.type=org.apache.hadoop.fs.azurebfs.oauth2.WorkloadIdentityTokenProvider",
    "-Dspark.hadoop.fs.azure.account.oauth2.client.id=${local.azure.workload_identity_client_id}",
    "-Dspark.hadoop.fs.azure.account.oauth2.msi.tenant=${local.azure.tenant_id}",
    "-Dspark.sql.catalog.spark_catalog.jdbc.schema-version=V1",
  ]
}
