locals {
  aws = merge({
    account_id               = ""
    flink_compute_role_arn   = ""
    polaris_storage_role_arn = ""
    kv_table_prefix          = ""
    kv_enable_ttl            = true
    kv_replica_regions       = []
    eks_log_group            = ""
    auth_secret_arn          = ""
    databricks_sp_secret_arn = ""
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
    secrets = merge(try(var.orchestration.secrets, {}), {
      extra_secret_objects = concat(
        try(var.orchestration.secrets.extra_secret_objects, []),
        local.databricks_secret_objects,
      )
    })
    provider_service_account_annotations = {
      "eks.amazonaws.com/role-arn" = local.aws.orchestration_role_arn
    }
    provider_runtime_env = local.runtime_env
    provider_hub_env     = local.hub_env
    provider_ui_env      = local.aws.eks_log_group == "" ? [] : [{ name = "AWS_EKS_LOG_GROUP", value = local.aws.eks_log_group }]
    provider_eval_env = concat(
      [{ name = "KV_TABLE_PREFIX", value = local.aws.kv_table_prefix }],
      local.databricks_env,
    )
  })

  deployment                  = local.orchestration.deployment
  database                    = local.orchestration.database
  compute                     = merge({ spark_event_log_dir = "" }, try(local.orchestration.compute, {}))
  spark_event_log_dir         = local.compute.spark_event_log_dir != "" ? local.compute.spark_event_log_dir : "s3a://${local.aws.warehouse_bucket}/spark-events"
  flink_compute_role_arn      = local.aws.flink_compute_role_arn != "" ? local.aws.flink_compute_role_arn : local.aws.spark_compute_role_arn
  database_host_with_port     = "${local.database.host}:${try(local.database.port, 5432)}"
  database_url                = try(local.database.url, "") != "" ? local.database.url : "postgres://$(DB_USERNAME)@${local.database_host_with_port}/${try(local.database.name, "execution_info")}?sslmode=require"
  hub_image                   = "ziplineai/hub-aws"
  eval_image                  = "ziplineai/eval-aws"
  hub_verticle_class          = "ai.chronon.hub.AWSOrchestrationVerticle,ai.chronon.hub.AWSWorkflowExecutionVerticle"
  polaris_base_location       = "s3://${local.aws.warehouse_bucket}/polaris/polaris_${local.deployment.customer_name}/"
  polaris_database_init_image = "public.ecr.aws/docker/library/postgres:16-alpine"
  auth_enabled                = try(local.orchestration.auth.enabled, false)

  ingress_lb_service = {
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type"   = "nlb"
      "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing"
    }
  }

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
    [
      { name = "KV_TABLE_PREFIX", value = local.aws.kv_table_prefix },
      { name = "KV_ENABLE_TTL", value = tostring(local.aws.kv_enable_ttl) },
      { name = "KV_REPLICA_REGIONS", value = join(",", local.aws.kv_replica_regions) },
      { name = "EKS_CLUSTER_NAME", value = local.aws.cluster_name },
    ],
    local.databricks_env,
  )

  provider_values = {
    database = {
      url = local.database_url
    }

    secrets = {
      provider = "aws"
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
        nvmeEnabled    = true
        nvmeSetupImage = "amazon/aws-cli:2.27.33"
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
              config = merge(
                { region = local.aws.region },
                local.aws.polaris_storage_role_arn == "" ? {} : { roleArn = local.aws.polaris_storage_role_arn },
              )
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
        service = local.ingress_lb_service
      }
    }
  }
}
