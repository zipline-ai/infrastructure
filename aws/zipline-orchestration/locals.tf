locals {
  image_pull_secret_name        = var.create_image_pull_secret ? kubernetes_secret_v1.docker_hub_creds[0].metadata[0].name : var.image_pull_secret_name
  spark_event_log_dir           = var.spark_event_log_dir != "" ? var.spark_event_log_dir : "s3a://${var.warehouse_bucket}/spark-events"
  flink_compute_role_arn        = var.flink_compute_role_arn != "" ? var.flink_compute_role_arn : var.spark_compute_role_arn
  fetcher_ingress_nginx_enabled = var.fetcher_ingress_nginx_enabled != null ? var.fetcher_ingress_nginx_enabled : var.deploy_fetcher
  compute_image_prepull_images  = length(var.compute_image_prepull_images) > 0 ? var.compute_image_prepull_images : (var.compute_image_prepull_enabled ? [var.spark_image] : [])
  database_host_with_port       = "${var.database_host}:${var.database_port}"
  database_url                  = var.database_url != "" ? var.database_url : "postgres://$(DB_USERNAME)@${local.database_host_with_port}/${var.database_name}?sslmode=require"

  cert_manager_annotations = var.cert_manager_cluster_issuer == "" ? {} : {
    "cert-manager.io/cluster-issuer" = var.cert_manager_cluster_issuer
  }

  aws_lb_annotations = merge({
    "service.beta.kubernetes.io/aws-load-balancer-type"   = "nlb"
    "service.beta.kubernetes.io/aws-load-balancer-scheme" = var.aws_load_balancer_scheme
  }, var.ingress_service_annotations)

  ui_lb_annotations      = merge(local.aws_lb_annotations, var.ui_ingress_service_annotations)
  hub_lb_annotations     = merge(local.aws_lb_annotations, var.hub_ingress_service_annotations)
  fetcher_lb_annotations = merge(local.aws_lb_annotations, var.fetcher_ingress_service_annotations)
  eval_lb_annotations    = merge(local.aws_lb_annotations, var.eval_ingress_service_annotations)

  ui_lb_service = merge(
    {
      annotations = local.ui_lb_annotations
    },
    length(merge(var.ingress_service_target_ports, var.ui_ingress_service_target_ports)) == 0 ? {} : {
      targetPorts = merge(var.ingress_service_target_ports, var.ui_ingress_service_target_ports)
    },
  )

  hub_lb_service = merge(
    {
      annotations = local.hub_lb_annotations
    },
    length(merge(var.ingress_service_target_ports, var.hub_ingress_service_target_ports)) == 0 ? {} : {
      targetPorts = merge(var.ingress_service_target_ports, var.hub_ingress_service_target_ports)
    },
  )

  fetcher_lb_service = merge(
    {
      annotations = local.fetcher_lb_annotations
    },
    length(merge(var.ingress_service_target_ports, var.fetcher_ingress_service_target_ports)) == 0 ? {} : {
      targetPorts = merge(var.ingress_service_target_ports, var.fetcher_ingress_service_target_ports)
    },
  )

  eval_lb_service = merge(
    {
      annotations = local.eval_lb_annotations
    },
    length(merge(var.ingress_service_target_ports, var.eval_ingress_service_target_ports)) == 0 ? {} : {
      targetPorts = merge(var.ingress_service_target_ports, var.eval_ingress_service_target_ports)
    },
  )

  ui_tls = var.ui_domain != "" && var.ui_tls_secret_name != "" ? [{
    hosts      = [var.ui_domain]
    secretName = var.ui_tls_secret_name
  }] : []

  hub_tls = var.hub_domain != "" && var.hub_tls_secret_name != "" ? [{
    hosts      = [var.hub_domain]
    secretName = var.hub_tls_secret_name
  }] : []

  fetcher_tls = var.fetcher_domain != "" && var.fetcher_tls_secret_name != "" ? [{
    hosts      = [var.fetcher_domain]
    secretName = var.fetcher_tls_secret_name
  }] : []

  eval_tls = var.eval_domain != "" && var.eval_tls_secret_name != "" ? [{
    hosts      = [var.eval_domain]
    secretName = var.eval_tls_secret_name
  }] : []

  auth_enabled = try(var.auth.enabled, false)

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
    var.extra_secret_objects,
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

  values = {
    global = {
      customer_name   = var.customer_name
      artifact_prefix = var.artifact_prefix
      version         = var.zipline_version
      deploy_fetcher  = var.deploy_fetcher
      cloud_provider  = "aws"
    }

    runtime = {
      env = concat(local.aws_runtime_env, var.runtime_env)
    }

    serviceAccount = {
      create = true
      name   = "orchestration-sa"
      annotations = {
        "eks.amazonaws.com/role-arn" = var.orchestration_role_arn
      }
    }

    imagePullSecrets = [
      {
        name = local.image_pull_secret_name
      }
    ]

    database = {
      jdbcUrl = var.database_jdbc_url
      url     = local.database_url
      host    = var.database_host
      port    = var.database_port
      name    = var.database_name
      sslMode = var.database_ssl_mode
      credentialsSecret = {
        name        = "db-credentials"
        usernameKey = "username"
        passwordKey = "password"
      }
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
      enabled          = true
      defaultNamespace = var.compute_default_namespace
      namespaces       = var.compute_namespaces
      objectStore = {
        bucket = var.warehouse_bucket
        region = var.region
      }
      serviceAccount = {
        sparkName = var.spark_service_account_name
        flinkName = var.flink_service_account_name
        annotations = {
          "eks.amazonaws.com/role-arn" = var.spark_compute_role_arn
        }
      }
      rbac = {
        create = var.compute_rbac_create
      }
      sparkDefaults = {
        eventLogDir    = local.spark_event_log_dir
        image          = var.spark_image
        nvmeEnabled    = var.spark_nvme_enabled
        nvmeSetupImage = var.spark_nvme_setup_image
      }
      flinkDefaults = {
        image          = var.flink_image
        serviceAccount = var.flink_service_account_name
        serviceAccountAnnotations = {
          "eks.amazonaws.com/role-arn" = local.flink_compute_role_arn
        }
      }
      imagePrepull = {
        enabled = var.compute_image_prepull_enabled
        images  = local.compute_image_prepull_images
      }
      historyServer = {
        image                 = var.spark_image
        extraSparkHistoryOpts = var.spark_history_extra_spark_opts
      }
    }

    polaris = {
      extraEnv = local.aws_runtime_env
      database = {
        initImage = var.polaris_database_init_image
      }
      bootstrap = {
        credentialsSecret = {
          name = var.polaris_bootstrap_credentials_secret
        }
        rbac = {
          catalog = {
            defaultBaseLocation = var.polaris_default_base_location
            storage = {
              type             = var.polaris_storage_type
              region           = var.region
              allowedLocations = var.polaris_allowed_locations
              config           = var.polaris_storage_config
            }
          }
        }
      }
    }

    orchestration = {
      hub = {
        image         = var.hub_image
        verticleClass = var.hub_verticle_class
        env           = concat(local.aws_hub_env, var.hub_env)
      }
      ui = {
        env = concat(local.aws_ui_env, var.ui_env)
      }
      fetcher = {
        replicas = var.fetcher_replicas
        env      = var.fetcher_env
      }
      eval = {
        image = var.eval_image
        env   = concat(local.aws_eval_env, var.eval_env)
      }
    }

    ingress = {
      ui = {
        className = var.ui_ingress_class_name
        host      = var.ui_domain
        path      = var.ui_ingress_path
        tls       = local.ui_tls
        annotations = merge(
          local.cert_manager_annotations,
          var.ingress_annotations,
          var.ui_ingress_annotations,
        )
      }
      hub = {
        className   = var.hub_ingress_class_name
        host        = var.hub_domain
        externalUrl = var.hub_external_url
        path        = var.hub_ingress_path
        tls         = local.hub_tls
        annotations = merge(
          {
            "nginx.ingress.kubernetes.io/health-check-path" = "/ping"
            "nginx.ingress.kubernetes.io/proxy-body-size"   = "20m"
          },
          local.cert_manager_annotations,
          var.ingress_annotations,
          var.hub_ingress_annotations,
        )
      }
      fetcher = {
        className = var.fetcher_ingress_class_name
        host      = var.fetcher_domain
        path      = var.fetcher_ingress_path
        tls       = local.fetcher_tls
        annotations = merge(
          {
            "nginx.ingress.kubernetes.io/health-check-path" = "/ping"
          },
          local.cert_manager_annotations,
          var.ingress_annotations,
          var.fetcher_ingress_annotations,
        )
      }
      eval = {
        className = var.eval_ingress_class_name
        host      = var.eval_domain
        path      = var.eval_ingress_path
        tls       = local.eval_tls
        annotations = merge(
          local.cert_manager_annotations,
          var.ingress_annotations,
          var.eval_ingress_annotations,
        )
      }
      polaris = {
        className = var.polaris_ingress_class_name
        path      = var.polaris_ingress_path
      }
    }

    "ingress-nginx-ui" = {
      enabled = var.ui_ingress_nginx_enabled
      controller = {
        service = local.ui_lb_service
      }
    }

    "ingress-nginx-hub" = {
      enabled = var.hub_ingress_nginx_enabled
      controller = {
        service = local.hub_lb_service
      }
    }

    "ingress-nginx-fetcher" = {
      enabled = local.fetcher_ingress_nginx_enabled
      controller = {
        service = local.fetcher_lb_service
      }
    }

    "ingress-nginx-eval" = {
      enabled = var.eval_ingress_nginx_enabled
      controller = {
        service = local.eval_lb_service
      }
    }

    prometheus = {
      queryEndpoint = var.prometheus_query_endpoint
      namespace     = var.namespace
    }

    auth = var.auth
  }
}
