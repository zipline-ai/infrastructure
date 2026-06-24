locals {
  orchestration = merge(var.orchestration, {
    install = merge({
      namespace    = "zipline-system"
      helm_wait    = true
      helm_timeout = 300
    }, try(var.orchestration.install, {}))
    image_pull_secret = merge({
      name               = "docker-hub-creds"
      create             = false
      dockerhub_username = "ziplineai"
      dockerhub_token    = ""
    }, try(var.orchestration.image_pull_secret, {}))
    database = merge({
      port     = 5432
      name     = "execution_info"
      ssl_mode = ""
      jdbc_url = ""
      url      = ""
    }, var.orchestration.database)
    ingress = merge({
      class_name                  = "nginx-ui"
      tls_secret_name             = ""
      cert_manager_cluster_issuer = ""
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
      install_secrets_store_csi_driver = true
      install_cert_manager             = true
      install_flink_operator           = true
      install_opentelemetry_operator   = false
    }, try(var.orchestration.addons, {}))
  })

  deployment                  = local.orchestration.deployment
  database                    = local.orchestration.database
  compute                     = local.orchestration.compute
  spark_event_log_dir         = local.compute.spark_event_log_dir != "" ? local.compute.spark_event_log_dir : "s3a://${var.warehouse_bucket}/spark-events"
  flink_compute_role_arn      = var.flink_compute_role_arn != "" ? var.flink_compute_role_arn : var.spark_compute_role_arn
  database_host_with_port     = "${local.database.host}:${local.database.port}"
  database_url                = local.database.url != "" ? local.database.url : "postgres://$(DB_USERNAME)@${local.database_host_with_port}/${local.database.name}?sslmode=require"
  hub_image                   = "ziplineai/hub-aws"
  eval_image                  = "ziplineai/eval-aws"
  hub_verticle_class          = "ai.chronon.hub.AWSOrchestrationVerticle,ai.chronon.hub.AWSWorkflowExecutionVerticle"
  polaris_base_location       = "s3://${var.warehouse_bucket}/polaris/polaris_${local.deployment.customer_name}/"
  polaris_database_init_image = "public.ecr.aws/docker/library/postgres:16-alpine"

  auth_enabled = try(local.orchestration.auth.enabled, false)

  aws_lb_annotations = merge({
    "service.beta.kubernetes.io/aws-load-balancer-type"   = "nlb"
    "service.beta.kubernetes.io/aws-load-balancer-scheme" = var.aws_load_balancer_scheme
  }, var.ingress_service_annotations)

  ingress_lb_service = merge(
    {
      annotations = local.aws_lb_annotations
    },
    length(var.ingress_service_target_ports) == 0 ? {} : {
      targetPorts = var.ingress_service_target_ports
    },
  )

  database_secret_object = {
    secretName = "db-credentials"
    type       = "Opaque"
    data = [
      {
        objectName = "password"
        key        = "password"
      },
      {
        objectName = "username"
        key        = "username"
      },
    ]
  }

  database_provider_object = {
    objectName = var.database_secret_arn
    objectType = "secretsmanager"
    jmesPath = [
      {
        path        = "password"
        objectAlias = "password"
      },
      {
        path        = "username"
        objectAlias = "username"
      },
    ]
  }

  databricks_secret_objects = var.databricks_sp_secret_arn == "" ? [] : [
    {
      secretName = "databricks-sp-credentials"
      type       = "Opaque"
      data = [
        {
          objectName = "client_id"
          key        = "client_id"
        },
        {
          objectName = "client_secret"
          key        = "client_secret"
        },
      ]
    }
  ]

  databricks_provider_objects = var.databricks_sp_secret_arn == "" ? [] : [
    {
      objectName = var.databricks_sp_secret_arn
      objectType = "secretsmanager"
      jmesPath = [
        {
          path        = "client_id"
          objectAlias = "client_id"
        },
        {
          path        = "client_secret"
          objectAlias = "client_secret"
        },
      ]
    }
  ]

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

  auth_provider_objects = local.auth_enabled ? [
    {
      objectName = var.auth_secret_arn
      objectType = "secretsmanager"
      jmesPath = [
        {
          path        = "\"auth-secret\""
          objectAlias = "auth-secret"
        },
        {
          path        = "\"google-oauth-client-secret\""
          objectAlias = "google-oauth-client-secret"
        },
        {
          path        = "\"github-oauth-client-secret\""
          objectAlias = "github-oauth-client-secret"
        },
        {
          path        = "\"microsoft-entra-oauth-client-secret\""
          objectAlias = "microsoft-entra-oauth-client-secret"
        },
        {
          path        = "\"sso-client-secret\""
          objectAlias = "sso-client-secret"
        },
      ]
    }
  ] : []

  secret_objects = concat(
    [local.database_secret_object],
    local.databricks_secret_objects,
    local.auth_secret_objects,
    try(local.orchestration.extra_secret_objects, []),
  )

  secret_provider_objects = concat(
    [local.database_provider_object],
    local.databricks_provider_objects,
    local.auth_provider_objects,
    var.extra_secret_provider_objects,
  )

  databricks_env = var.databricks_sp_secret_arn == "" ? [] : [
    {
      name = "DATABRICKS_CLIENT_ID"
      valueFrom = {
        secretKeyRef = {
          name = "databricks-sp-credentials"
          key  = "client_id"
        }
      }
    },
    {
      name = "DATABRICKS_CLIENT_SECRET"
      valueFrom = {
        secretKeyRef = {
          name = "databricks-sp-credentials"
          key  = "client_secret"
        }
      }
    },
  ]

  aws_runtime_env = [
    {
      name  = "AWS_REGION"
      value = var.region
    },
    {
      name  = "AWS_DEFAULT_REGION"
      value = var.region
    },
  ]

  aws_hub_env = concat(
    var.chronon_metrics_reader == "" ? [] : [
      {
        name  = "CHRONON_METRICS_READER"
        value = var.chronon_metrics_reader
      }
    ],
    [
      {
        name  = "KV_TABLE_PREFIX"
        value = var.kv_table_prefix
      },
      {
        name  = "KV_ENABLE_TTL"
        value = tostring(var.kv_enable_ttl)
      },
      {
        name  = "KV_REPLICA_REGIONS"
        value = join(",", var.kv_replica_regions)
      },
      {
        name  = "EKS_CLUSTER_NAME"
        value = var.cluster_name
      },
    ],
    local.databricks_env,
  )

  aws_eval_env = concat(
    [
      {
        name  = "KV_TABLE_PREFIX"
        value = var.kv_table_prefix
      },
    ],
    local.databricks_env,
  )

  aws_ui_env = var.aws_eks_log_group == "" ? [] : [
    {
      name  = "AWS_EKS_LOG_GROUP"
      value = var.aws_eks_log_group
    },
  ]

  provider_values = {
    global = {
      cloud_provider = "aws"
    }

    runtime = {
      env = concat(local.aws_runtime_env, try(local.orchestration.runtime_env, []))
    }

    serviceAccount = {
      create = true
      name   = "orchestration-sa"
      annotations = {
        "eks.amazonaws.com/role-arn" = var.orchestration_role_arn
      }
    }

    database = {
      url = local.database_url
    }

    secrets = {
      enabled       = true
      provider      = "aws"
      className     = var.secret_provider_class_name
      secretObjects = local.secret_objects
      parameters = {
        objects = yamlencode(local.secret_provider_objects)
      }
    }

    compute = {
      objectStore = {
        bucket = var.warehouse_bucket
        region = var.region
      }
      serviceAccount = {
        annotations = {
          "eks.amazonaws.com/role-arn" = var.spark_compute_role_arn
        }
      }
      sparkDefaults = {
        eventLogDir    = local.spark_event_log_dir
        nvmeEnabled    = var.spark_nvme_enabled
        nvmeSetupImage = var.spark_nvme_setup_image
      }
      flinkDefaults = {
        serviceAccountAnnotations = {
          "eks.amazonaws.com/role-arn" = local.flink_compute_role_arn
        }
      }
    }

    polaris = {
      extraEnv = local.aws_runtime_env
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
              config           = merge({ region = var.region }, var.polaris_storage_config)
            }
          }
        }
      }
    }

    orchestration = {
      hub = {
        image         = local.hub_image
        verticleClass = local.hub_verticle_class
        env           = concat(local.aws_hub_env, try(local.orchestration.hub_env, []))
      }
      ui = {
        env = concat(local.aws_ui_env, var.ui_env)
      }
      fetcher = {
        env = var.fetcher_env
      }
      eval = {
        image = local.eval_image
        env   = concat(local.aws_eval_env, var.eval_env)
      }
    }

    "ingress-nginx-ui" = {
      controller = {
        service = local.ingress_lb_service
      }
    }
  }
}
