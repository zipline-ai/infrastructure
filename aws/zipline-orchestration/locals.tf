locals {
  cloud_args = merge({
    cluster_name                   = ""
    eks_version                    = "1.35"
    eks_instance_type              = "m8a.4xlarge"
    eks_desired_size               = 3
    eks_min_size                   = 3
    eks_max_size                   = 8
    eks_disk_size                  = 100
    personnel_arns                 = []
    kv_table_prefix                = ""
    kv_enable_ttl                  = true
    kv_replica_regions             = []
    kv_read_capacity               = 10
    kv_write_capacity              = 10
    eks_log_group                  = ""
    auth_secret_arn                = ""
    auth_secret_values             = {}
    extra_external_secrets         = []
    extra_secret_arns              = []
    additional_data_buckets        = []
    additional_flink_s3_buckets    = []
    shared_warehouse_bucket        = ""
    spark_libs_bucket              = ""
    logs_bucket                    = ""
    glue_schema_registry_name      = ""
    msk_cluster_arn                = ""
    amp_workspace_arn              = ""
    encryption_kms_key_arn         = ""
    encryption_kms_key_arns        = {}
    database_name                  = "execution_info"
    database_username              = "locker_user"
    database_instance_class        = "db.t3.medium"
    database_allocated_storage     = 20
    database_multi_az              = true
    database_publicly_accessible   = false
    database_backup_retention_days = 7
  }, var.aws)

  install                       = try(var.orchestration.install, {})
  deployment                    = var.orchestration.deployment
  name_prefix                   = local.deployment.customer_name
  cluster_name                  = local.cloud_args.cluster_name != "" ? local.cloud_args.cluster_name : "${local.name_prefix}-eks"
  orchestration_namespace       = try(local.install.namespace, "zipline-system")
  orchestration_service_account = try(var.orchestration.service_account.name, "orchestration-sa")
  compute_namespace_prefix      = try(local.cloud_args.compute_namespace_prefix, "zipline-")
  spark_service_account         = try(var.orchestration.compute.spark_service_account, "spark-operator-spark")
  flink_service_account         = try(var.orchestration.compute.flink_service_account, "flink")

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

  auth_enabled               = try(var.orchestration.auth.enabled, false)
  configured_auth_secret_arn = try(local.cloud_args.auth_secret_arn, try(var.orchestration.auth.secrets_arn, ""))
  create_auth_secret         = local.auth_enabled && length(keys(local.cloud_args.auth_secret_values)) > 0
  auth_secret_arn            = local.create_auth_secret ? aws_secretsmanager_secret.zipline_auth[0].arn : local.configured_auth_secret_arn

  extra_external_secrets = try(local.cloud_args.extra_external_secrets, [])
  extra_external_secret_arns = distinct(compact(concat(
    try(local.cloud_args.extra_secret_arns, []),
    flatten([
      for external_secret in local.extra_external_secrets : [
        for item in try(external_secret.spec.data, []) : tostring(try(item.remoteRef.key, ""))
        if startswith(tostring(try(item.remoteRef.key, "")), "arn:")
      ]
    ]),
  )))

  provider_context = {
    database = {
      host = aws_db_instance.zipline.address
      port = aws_db_instance.zipline.port
      name = local.cloud_args.database_name
    }
    prometheus = {
      query_endpoint = aws_prometheus_workspace.main.prometheus_endpoint
    }
    hub = {
      image          = local.hub_image
      verticle_class = local.hub_verticle_class
    }
    eval = {
      image = local.eval_image
    }
    compute = {
      object_store = {
        bucket = local.cloud_args.warehouse_bucket
        region = local.cloud_args.region
      }
      spark_event_log_dir    = local.spark_event_log_dir
      history_server_options = local.spark_history_opts
      service_account = {
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.spark_compute_execution.arn
        }
      }
      spark_defaults = {
        nvmeEnabled    = true
        nvmeSetupImage = "amazon/aws-cli:2.27.33"
      }
      flink_defaults = {
        serviceAccountAnnotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.flink_compute_execution.arn
        }
      }
    }
    service_account_annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.orchestration_irsa.arn
    }
    secrets = {
      secret_store = {
        create = true
        name   = "zipline-secret-store"
        kind   = "SecretStore"
        spec = {
          provider = {
            aws = {
              service = "SecretsManager"
              region  = local.cloud_args.region
              auth = {
                jwt = {
                  serviceAccountRef = {
                    name = local.orchestration_service_account
                  }
                }
              }
            }
          }
        }
      }
      database_remote_refs = {
        username = {
          key      = aws_secretsmanager_secret.db_credentials.arn
          property = "username"
        }
        password = {
          key      = aws_secretsmanager_secret.db_credentials.arn
          property = "password"
        }
      }
      auth_remote_refs = {
        for key in local.auth_secret_keys : key => {
          key      = local.auth_secret_arn
          property = key
        }
      }
      extra_external_secrets = local.extra_external_secrets
    }
    runtime_env = [
      { name = "AWS_DEFAULT_REGION", value = local.cloud_args.region },
    ]
    hub_env = concat(
      local.cloud_args.kv_table_prefix == "" ? [] : [{ name = "KV_TABLE_PREFIX", value = local.cloud_args.kv_table_prefix }],
      local.cloud_args.kv_enable_ttl ? [] : [{ name = "KV_ENABLE_TTL", value = tostring(local.cloud_args.kv_enable_ttl) }],
      length(local.cloud_args.kv_replica_regions) == 0 ? [] : [{ name = "KV_REPLICA_REGIONS", value = join(",", local.cloud_args.kv_replica_regions) }],
      [
        {
          name = "OC_CREDENTIAL"
          valueFrom = {
            secretKeyRef = {
              name     = local.polaris_client_secret_name
              key      = local.polaris_client_secret_key
              optional = true
            }
          }
        }
      ],
    )
    ui_env = local.eks_log_group == "" ? [] : [{ name = "AWS_EKS_LOG_GROUP", value = local.eks_log_group }]
    values = local.provider_values
  }

  spark_event_log_dir = try(var.orchestration.compute.spark_event_log_dir, "") != "" ? var.orchestration.compute.spark_event_log_dir : "s3a://${local.cloud_args.warehouse_bucket}/spark-events"
  spark_history_opts = [
    "-Dspark.hadoop.fs.s3a.aws.credentials.provider=com.amazonaws.auth.WebIdentityTokenCredentialsProvider",
    "-Dspark.hadoop.fs.s3a.connection.maximum=200",
    "-Dspark.hadoop.fs.s3a.threads.max=50",
  ]
  hub_image                   = "ziplineai/hub-aws"
  eval_image                  = "ziplineai/eval-aws"
  hub_verticle_class          = "ai.chronon.hub.AWSOrchestrationVerticle,ai.chronon.hub.AWSWorkflowExecutionVerticle"
  polaris_base_location       = "s3://${local.cloud_args.warehouse_bucket}/polaris/polaris_${local.deployment.customer_name}/"
  polaris_client_secret_name  = "polaris-client-credentials"
  polaris_client_secret_key   = "OC_CREDENTIAL"
  polaris_storage_external_id = "zipline:${local.name_prefix}:polaris-storage"
  polaris_storage_allowed_buckets = distinct(compact([
    for bucket in [local.cloud_args.warehouse_bucket] :
    trimsuffix(trimprefix(trimprefix(trimspace(bucket), "s3://"), "s3a://"), "/")
  ]))
  polaris_storage_allowed_locations = [
    for bucket in local.polaris_storage_allowed_buckets : "s3://${bucket}/"
  ]
  polaris_storage_allowed_kms_keys = distinct(compact(concat(
    [local.cloud_args.encryption_kms_key_arn],
    values(local.cloud_args.encryption_kms_key_arns),
  )))
  artifact_bucket      = split("/", trimsuffix(trimprefix(trimspace(local.deployment.artifact_prefix), "s3://"), "/"))[0]
  logs_bucket          = local.cloud_args.logs_bucket != "" ? local.cloud_args.logs_bucket : "zipline-logs-${local.name_prefix}"
  glue_registry_name   = local.cloud_args.glue_schema_registry_name != "" ? local.cloud_args.glue_schema_registry_name : "zipline-${local.name_prefix}"
  msk_topic_arn_prefix = local.cloud_args.msk_cluster_arn != "" ? replace(local.cloud_args.msk_cluster_arn, ":cluster/", ":topic/") : ""
  msk_group_arn_prefix = local.cloud_args.msk_cluster_arn != "" ? replace(local.cloud_args.msk_cluster_arn, ":cluster/", ":group/") : ""
  eks_log_group        = local.cloud_args.eks_log_group != "" ? local.cloud_args.eks_log_group : "/aws/eks/${local.cluster_name}/containers"
  amp_workspace_arn    = local.cloud_args.amp_workspace_arn != "" ? local.cloud_args.amp_workspace_arn : aws_prometheus_workspace.main.arn
  orchestration_s3_read_buckets = distinct(compact(concat(
    [local.cloud_args.shared_warehouse_bucket],
    local.cloud_args.additional_data_buckets,
  )))
  spark_compute_s3_buckets = distinct(compact(concat(
    [
      local.cloud_args.warehouse_bucket,
      local.artifact_bucket,
      local.cloud_args.spark_libs_bucket,
      local.logs_bucket,
    ],
    local.cloud_args.additional_data_buckets,
  )))
  flink_compute_s3_buckets = distinct(compact(concat(
    [
      local.cloud_args.warehouse_bucket,
      local.artifact_bucket,
      local.cloud_args.spark_libs_bucket,
      local.logs_bucket,
    ],
    local.cloud_args.additional_flink_s3_buckets,
  )))

  ingress_lb_service = {
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type"    = "nlb"
      "service.beta.kubernetes.io/aws-load-balancer-scheme"  = "internet-facing"
      "service.beta.kubernetes.io/aws-load-balancer-subnets" = join(",", [local.cloud_args.primary_subnet_id, local.cloud_args.secondary_subnet_id])
    }
  }

  provider_values = {
    polaris = {
      extraEnv = [
        { name = "AWS_DEFAULT_REGION", value = local.cloud_args.region },
      ]
      bootstrap = {
        runtimeClient = {
          credentialsSecret = {
            name = local.polaris_client_secret_name
            key  = local.polaris_client_secret_key
          }
        }
        rbac = {
          catalog = {
            defaultBaseLocation = local.polaris_base_location
            storage = {
              type             = "S3"
              allowedLocations = local.polaris_storage_allowed_locations
              config = {
                region     = local.cloud_args.region
                roleArn    = aws_iam_role.polaris_storage.arn
                externalId = local.polaris_storage_external_id
              }
            }
          }
        }
      }
    }

    compute = {
      historyServer = {
        persistence = {
          storageClass = kubernetes_storage_class_v1.gp3.metadata[0].name
        }
      }
      loki = {
        storage = {
          storageClass = kubernetes_storage_class_v1.gp3.metadata[0].name
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
