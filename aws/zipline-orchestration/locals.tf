locals {
  aws = merge({
    account_id                         = ""
    vpc_id                             = ""
    flink_compute_role_arn             = ""
    spark_nvme_enabled                 = false
    spark_nvme_setup_image             = ""
    polaris_storage_config             = {}
    secret_provider_class_name         = "zipline-secret-provider"
    kv_table_prefix                    = ""
    kv_enable_ttl                      = true
    kv_replica_regions                 = []
    chronon_metrics_reader             = "http"
    eks_log_group                      = ""
    auth_secret_arn                    = ""
    databricks_sp_secret_arn           = ""
    eval_env                           = []
    ui_env                             = []
    fetcher_env                        = []
    install_secrets_store_csi_provider = true
    install_load_balancer_controller   = true
    load_balancer_controller_role_arn  = ""
    load_balancer_controller_version   = "1.7.1"
    load_balancer_scheme               = "internet-facing"
    ingress_service_annotations        = {}
    ingress_service_target_ports       = {}
    extra_secret_provider_objects      = []
  }, var.aws)

  auth_secret_keys = [
    "auth-secret",
    "google-oauth-client-secret",
    "github-oauth-client-secret",
    "microsoft-entra-oauth-client-secret",
    "sso-client-secret",
  ]

  databricks_secret_keys = ["client_id", "client_secret"]
  databricks_secret_objects = local.aws.databricks_sp_secret_arn == "" ? [] : [
    {
      secretName = "databricks-sp-credentials"
      type       = "Opaque"
      data       = [for key in local.databricks_secret_keys : { objectName = key, key = key }]
    }
  ]

  orchestration = merge(var.orchestration, {
    image_pull_secret = merge({
      name = "docker-hub-creds"
    }, try(var.orchestration.image_pull_secret, {}))
    database = merge({
      port     = 5432
      name     = "execution_info"
      ssl_mode = ""
      jdbc_url = ""
      url      = ""
    }, var.orchestration.database)
    secrets = merge(try(var.orchestration.secrets, {}), {
      extra_secret_objects = concat(
        try(var.orchestration.secrets.extra_secret_objects, []),
        local.databricks_secret_objects,
      )
    })
  })

  deployment                  = local.orchestration.deployment
  database                    = local.orchestration.database
  compute                     = merge({ spark_event_log_dir = "" }, try(local.orchestration.compute, {}))
  spark_event_log_dir         = local.compute.spark_event_log_dir != "" ? local.compute.spark_event_log_dir : "s3a://${local.aws.warehouse_bucket}/spark-events"
  flink_compute_role_arn      = local.aws.flink_compute_role_arn != "" ? local.aws.flink_compute_role_arn : local.aws.spark_compute_role_arn
  database_host_with_port     = "${local.database.host}:${local.database.port}"
  database_url                = local.database.url != "" ? local.database.url : "postgres://$(DB_USERNAME)@${local.database_host_with_port}/${local.database.name}?sslmode=require"
  hub_image                   = "ziplineai/hub-aws"
  eval_image                  = "ziplineai/eval-aws"
  hub_verticle_class          = "ai.chronon.hub.AWSOrchestrationVerticle,ai.chronon.hub.AWSWorkflowExecutionVerticle"
  polaris_base_location       = "s3://${local.aws.warehouse_bucket}/polaris/polaris_${local.deployment.customer_name}/"
  polaris_database_init_image = "public.ecr.aws/docker/library/postgres:16-alpine"
  auth_enabled                = try(local.orchestration.auth.enabled, false)

  ingress_lb_service = merge(
    {
      annotations = merge({
        "service.beta.kubernetes.io/aws-load-balancer-type"   = "nlb"
        "service.beta.kubernetes.io/aws-load-balancer-scheme" = local.aws.load_balancer_scheme
      }, local.aws.ingress_service_annotations)
    },
    length(local.aws.ingress_service_target_ports) == 0 ? {} : {
      targetPorts = local.aws.ingress_service_target_ports
    },
  )

  secret_provider_objects = concat(
    [
      {
        objectName = local.aws.database_secret_arn
        objectType = "secretsmanager"
        jmesPath = [
          { path = "password", objectAlias = "password" },
          { path = "username", objectAlias = "username" },
        ]
      }
    ],
    local.aws.databricks_sp_secret_arn == "" ? [] : [
      {
        objectName = local.aws.databricks_sp_secret_arn
        objectType = "secretsmanager"
        jmesPath   = [for key in local.databricks_secret_keys : { path = key, objectAlias = key }]
      }
    ],
    local.auth_enabled ? [
      {
        objectName = local.aws.auth_secret_arn
        objectType = "secretsmanager"
        jmesPath   = [for key in local.auth_secret_keys : { path = "\"${key}\"", objectAlias = key }]
      }
    ] : [],
    local.aws.extra_secret_provider_objects,
  )

  databricks_env = local.aws.databricks_sp_secret_arn == "" ? [] : [
    for key in local.databricks_secret_keys : {
      name = upper("DATABRICKS_${key}")
      valueFrom = {
        secretKeyRef = {
          name = "databricks-sp-credentials"
          key  = key
        }
      }
    }
  ]

  runtime_env = [
    { name = "AWS_REGION", value = local.aws.region },
    { name = "AWS_DEFAULT_REGION", value = local.aws.region },
  ]

  hub_env = concat(
    local.aws.chronon_metrics_reader == "" ? [] : [
      { name = "CHRONON_METRICS_READER", value = local.aws.chronon_metrics_reader }
    ],
    [
      { name = "KV_TABLE_PREFIX", value = local.aws.kv_table_prefix },
      { name = "KV_ENABLE_TTL", value = tostring(local.aws.kv_enable_ttl) },
      { name = "KV_REPLICA_REGIONS", value = join(",", local.aws.kv_replica_regions) },
      { name = "EKS_CLUSTER_NAME", value = local.aws.cluster_name },
    ],
    local.databricks_env,
  )

  provider_values = {
    global = {
      cloud_provider = "aws"
    }

    runtime = {
      env = concat(local.runtime_env, try(local.orchestration.runtime_env, []))
    }

    serviceAccount = {
      create = true
      name   = "orchestration-sa"
      annotations = {
        "eks.amazonaws.com/role-arn" = local.aws.orchestration_role_arn
      }
    }

    database = {
      url = local.database_url
    }

    secrets = {
      enabled   = true
      provider  = "aws"
      className = local.aws.secret_provider_class_name
      parameters = {
        objects = yamlencode(local.secret_provider_objects)
      }
    }

    compute = {
      objectStore = {
        bucket = local.aws.warehouse_bucket
        region = local.aws.region
      }
      serviceAccount = {
        annotations = {
          "eks.amazonaws.com/role-arn" = local.aws.spark_compute_role_arn
        }
      }
      sparkDefaults = {
        eventLogDir    = local.spark_event_log_dir
        nvmeEnabled    = local.aws.spark_nvme_enabled
        nvmeSetupImage = local.aws.spark_nvme_setup_image
      }
      flinkDefaults = {
        serviceAccountAnnotations = {
          "eks.amazonaws.com/role-arn" = local.flink_compute_role_arn
        }
      }
    }

    polaris = {
      extraEnv = local.runtime_env
      database = {
        initImage = local.polaris_database_init_image
      }
      bootstrap = {
        rbac = {
          catalog = {
            defaultBaseLocation = local.polaris_base_location
            storage = {
              type             = "S3"
              allowedLocations = [local.polaris_base_location]
              config           = merge({ region = local.aws.region }, local.aws.polaris_storage_config)
            }
          }
        }
      }
    }

    orchestration = {
      hub = {
        image         = local.hub_image
        verticleClass = local.hub_verticle_class
        env           = concat(local.hub_env, try(local.orchestration.hub_env, []))
      }
      ui = {
        env = concat(
          local.aws.eks_log_group == "" ? [] : [{ name = "AWS_EKS_LOG_GROUP", value = local.aws.eks_log_group }],
          local.aws.ui_env,
        )
      }
      fetcher = {
        env = local.aws.fetcher_env
      }
      eval = {
        image = local.eval_image
        env   = concat([{ name = "KV_TABLE_PREFIX", value = local.aws.kv_table_prefix }], local.databricks_env, local.aws.eval_env)
      }
    }

    "ingress-nginx-ui" = {
      controller = {
        service = local.ingress_lb_service
      }
    }
  }
}
