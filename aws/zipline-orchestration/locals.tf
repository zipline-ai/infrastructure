locals {
  cloud_args = merge({
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

  databricks_secret_keys = ["client_id", "client_secret"]
  databricks_secret_objects = local.cloud_args.databricks_sp_secret_arn == "" ? [] : [
    {
      secretName = "databricks-sp-credentials"
      type       = "Opaque"
      data       = [for key in local.databricks_secret_keys : { objectName = key, key = key }]
    }
  ]

  compute_input = try(var.orchestration.compute, {})

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
        bucket = local.cloud_args.warehouse_bucket
        region = local.cloud_args.region
      }
      spark_event_log_dir = local.spark_event_log_dir
      service_account = merge(try(local.compute_input.service_account, {}), {
        annotations = {
          "eks.amazonaws.com/role-arn" = local.cloud_args.spark_compute_role_arn
        }
      })
      spark_defaults = merge(try(local.compute_input.spark_defaults, {}), {
        nvmeEnabled    = true
        nvmeSetupImage = "amazon/aws-cli:2.27.33"
      })
      flink_defaults = merge(try(local.compute_input.flink_defaults, {}), {
        serviceAccountAnnotations = {
          "eks.amazonaws.com/role-arn" = local.flink_compute_role_arn
        }
      })
    })
    secrets = merge(try(var.orchestration.secrets, {}), {
      extra_secret_objects = concat(
        try(var.orchestration.secrets.extra_secret_objects, []),
        local.databricks_secret_objects,
      )
    })
    provider_service_account_annotations = {
      "eks.amazonaws.com/role-arn" = local.cloud_args.orchestration_role_arn
    }
    provider_runtime_env = local.runtime_env
    provider_hub_env     = local.hub_env
    provider_ui_env      = local.cloud_args.eks_log_group == "" ? [] : [{ name = "AWS_EKS_LOG_GROUP", value = local.cloud_args.eks_log_group }]
    provider_eval_env = concat(
      [{ name = "KV_TABLE_PREFIX", value = local.cloud_args.kv_table_prefix }],
      local.databricks_env,
    )
    values = local.provider_values
  })

  deployment                  = var.orchestration.deployment
  spark_event_log_dir         = try(local.compute_input.spark_event_log_dir, "") != "" ? local.compute_input.spark_event_log_dir : "s3a://${local.cloud_args.warehouse_bucket}/spark-events"
  flink_compute_role_arn      = local.cloud_args.flink_compute_role_arn != "" ? local.cloud_args.flink_compute_role_arn : local.cloud_args.spark_compute_role_arn
  hub_image                   = "ziplineai/hub-aws"
  eval_image                  = "ziplineai/eval-aws"
  hub_verticle_class          = "ai.chronon.hub.AWSOrchestrationVerticle,ai.chronon.hub.AWSWorkflowExecutionVerticle"
  polaris_base_location       = "s3://${local.cloud_args.warehouse_bucket}/polaris/polaris_${local.deployment.customer_name}/"
  polaris_database_init_image = "public.ecr.aws/docker/library/postgres:16-alpine"
  auth_enabled                = try(var.orchestration.auth.enabled, false)

  ingress_lb_service = {
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type"   = "nlb"
      "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing"
    }
  }

  secret_provider_objects = concat(
    [
      {
        objectName = local.cloud_args.database_secret_arn
        objectType = "secretsmanager"
        jmesPath = [
          { path = "password", objectAlias = "password" },
          { path = "username", objectAlias = "username" },
        ]
      }
    ],
    local.cloud_args.databricks_sp_secret_arn == "" ? [] : [
      {
        objectName = local.cloud_args.databricks_sp_secret_arn
        objectType = "secretsmanager"
        jmesPath   = [for key in local.databricks_secret_keys : { path = key, objectAlias = key }]
      }
    ],
    local.auth_enabled ? [
      {
        objectName = local.cloud_args.auth_secret_arn
        objectType = "secretsmanager"
        jmesPath   = [for key in local.auth_secret_keys : { path = "\"${key}\"", objectAlias = key }]
      }
    ] : [],
  )

  databricks_env = local.cloud_args.databricks_sp_secret_arn == "" ? [] : [
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
    { name = "AWS_REGION", value = local.cloud_args.region },
    { name = "AWS_DEFAULT_REGION", value = local.cloud_args.region },
  ]

  hub_env = concat(
    [
      { name = "KV_TABLE_PREFIX", value = local.cloud_args.kv_table_prefix },
      { name = "KV_ENABLE_TTL", value = tostring(local.cloud_args.kv_enable_ttl) },
      { name = "KV_REPLICA_REGIONS", value = join(",", local.cloud_args.kv_replica_regions) },
      { name = "EKS_CLUSTER_NAME", value = local.cloud_args.cluster_name },
    ],
    local.databricks_env,
  )

  provider_values = {
    secrets = {
      provider = "aws"
      parameters = {
        objects = yamlencode(local.secret_provider_objects)
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
                { region = local.cloud_args.region },
                local.cloud_args.polaris_storage_role_arn == "" ? {} : { roleArn = local.cloud_args.polaris_storage_role_arn },
              )
            }
          }
        }
      }
    }

    "ingress-nginx-ui" = {
      controller = {
        service = local.ingress_lb_service
      }
    }
  }
}
