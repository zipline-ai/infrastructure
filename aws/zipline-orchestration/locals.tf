locals {
  cloud_args = merge({
    cluster_name                         = ""
    eks_version                          = "1.36"
    eks_instance_type                    = "m8a.4xlarge"
    eks_desired_size                     = 3
    eks_min_size                         = 3
    eks_max_size                         = 8
    eks_disk_size                        = 100
    ingress_traffic_policy               = "Cluster"
    personnel_arns                       = []
    kv_table_prefix                      = ""
    kv_enable_ttl                        = true
    kv_replica_regions                   = []
    kv_batch_table_gc_age_days           = ""
    kv_read_capacity                     = 10
    kv_write_capacity                    = 10
    eks_log_group                        = ""
    auth_secret_arn                      = ""
    extra_external_secrets               = []
    extra_secret_arns                    = []
    additional_data_buckets              = []
    additional_flink_s3_buckets          = []
    additional_flink_readonly_s3_buckets = []
    shared_warehouse_bucket              = ""
    spark_libs_bucket                    = ""
    logs_bucket                          = ""
    glue_schema_registry_name            = ""
    msk_cluster_arn                      = ""
    databricks_client_id                 = ""
    databricks_client_secret             = ""
    amp_workspace_arn                    = ""
    encryption_kms_key_arn               = ""
    encryption_kms_key_arns              = {}
    database_name                        = "execution_info"
    database_username                    = "locker_user"
    database_instance_class              = "db.t3.medium"
    database_allocated_storage           = 20
    database_multi_az                    = true
    database_publicly_accessible         = false
    database_backup_retention_days       = 7
    # Prod-safe default: take a final snapshot on destroy. Test/POC accounts set
    # aws.database_skip_final_snapshot = true for clean, snapshot-free teardown.
    database_skip_final_snapshot = false
    # Prod-safe default: refuse to destroy non-empty artifact/warehouse/logs
    # buckets. Test/POC accounts set aws.bucket_force_destroy = true so tofu
    # empties and deletes them on teardown instead of failing with BucketNotEmpty.
    bucket_force_destroy = false
    # Prod-safe default: Secrets Manager secrets keep the 30-day recovery window on
    # destroy, so their names stay reserved. Test/POC accounts set
    # aws.secret_force_delete = true so teardown force-deletes them (recovery window
    # 0) and the names are immediately free for the next apply.
    secret_force_delete = false
    karpenter           = {}
  }, var.aws)

  redis = merge({
    enabled             = false
    cluster_nodes       = ""
    password_secret_arn = ""
    password_secret_key = "password"
    use_ssl             = true
    node_type           = "cache.t4g.small"
    shards              = 1
    replicas_per_shard  = 1
  }, try(local.cloud_args.redis, {}))
  redis_managed = local.redis.enabled && trimspace(local.redis.cluster_nodes) == ""
  redis_password_secret_arn = local.redis.enabled ? (
    local.redis_managed ? try(aws_secretsmanager_secret.redis[0].arn, "") : trimspace(local.redis.password_secret_arn)
  ) : ""
  redis_cluster_nodes = local.redis.enabled ? (
    local.redis_managed ? "${aws_elasticache_replication_group.redis[0].configuration_endpoint_address}:6379" : trimspace(local.redis.cluster_nodes)
  ) : ""

  # When no VPC is supplied, provision one (network.tf) and resolve ids here.
  # Kept out of cloud_args: the aws provider reads cloud_args.region, so folding
  # these resource refs into cloud_args would cycle provider -> network -> provider.
  create_network               = trimspace(tostring(try(var.aws.vpc_id, ""))) == ""
  resolved_vpc_id              = local.create_network ? aws_vpc.main[0].id : trimspace(tostring(try(var.aws.vpc_id, "")))
  resolved_primary_subnet_id   = local.create_network ? aws_subnet.zipline["primary"].id : trimspace(tostring(try(var.aws.primary_subnet_id, "")))
  resolved_secondary_subnet_id = local.create_network ? aws_subnet.zipline["secondary"].id : trimspace(tostring(try(var.aws.secondary_subnet_id, "")))

  install                       = try(var.orchestration.install, {})
  deployment                    = var.orchestration.deployment
  deploy_fetcher                = try(local.deployment.deploy_fetcher, false)
  name_prefix                   = local.deployment.customer_name
  cluster_name                  = local.cloud_args.cluster_name != "" ? local.cloud_args.cluster_name : "${local.name_prefix}-eks"
  orchestration_namespace       = try(local.install.namespace, "zipline-system")
  orchestration_service_account = try(var.orchestration.service_account.name, "orchestration-sa")
  compute_namespace_prefix      = try(local.cloud_args.compute_namespace_prefix, "zipline-")
  spark_service_account         = try(var.orchestration.compute.spark_service_account, "spark-operator-spark")
  flink_service_account         = try(var.orchestration.compute.flink_service_account, "flink")

  karpenter = merge({
    enabled            = true
    namespace          = "kube-system"
    release_name       = "karpenter"
    version            = "1.13.0"
    enable_zonal_shift = false
    values             = {}
    # Overrides only. The real EC2NodeClass defaults — AMI, encrypted gp3+KMS
    # root volume, and IMDSv2 (httpTokens=required) — are computed in
    # karpenter_ec2_node_class below. This must stay sparse: merge() lets a
    # later map win even when a key is {} or [], so non-empty defaults here
    # (e.g. metadata_options={}, block_device_mappings=[]) would clobber the
    # computed values and silently drop encryption + IMDSv2.
    ec2_node_class = {}
    node_pools     = {}
  }, local.cloud_args.karpenter)
  karpenter_ec2_node_class = merge({
    name       = "zipline"
    ami_family = "AL2023"
    # Pinned to a specific AL2023 release for reproducible node provisioning
    # (vs @latest, which silently rolls). Bump via aws.karpenter.ami_alias; look
    # up newer releases with the EKS SSM optimized-ami release_version parameter.
    ami_alias        = try(local.karpenter.ami_alias, "al2023@v20260625")
    instance_profile = try(aws_iam_instance_profile.karpenter_node[0].name, "")
    subnet_selector_terms = [
      { id = local.resolved_primary_subnet_id },
      { id = local.resolved_secondary_subnet_id },
    ]
    security_group_selector_terms = [
      { id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id },
    ]
    metadata_options = {
      httpEndpoint            = "enabled"
      httpTokens              = "required"
      httpPutResponseHopLimit = 2
    }
    block_device_mappings = [
      {
        deviceName = "/dev/xvda"
        ebs = {
          volumeSize          = "${local.cloud_args.eks_disk_size}Gi"
          volumeType          = "gp3"
          encrypted           = true
          kmsKeyID            = aws_kms_key.eks_node_root.arn
          deleteOnTermination = true
        }
      }
    ]
    # Let Karpenter bootstrap AL2023 instance-store disks as node ephemeral
    # storage. Spark then uses its standard emptyDir local directories without
    # knowing which hardware backs them.
    instance_store_policy = "RAID0"
    tags                  = {}
    user_data             = ""
  }, try(local.karpenter.ec2_node_class, {}))

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

  auth_enabled = try(var.orchestration.auth.enabled, false)

  auth_secret_arn = try(coalesce(
    try(local.cloud_args.auth_secret_arn, ""),
    try(var.orchestration.auth.secrets_arn, ""),
  ), "")

  legacy_extra_secret_provider_objects = try(local.cloud_args.extra_secret_provider_objects, [])
  legacy_extra_secret_objects          = try(var.orchestration.secrets.extra_secret_objects, [])
  legacy_secret_provider_alias_refs = merge(
    {},
    [
      for object in local.legacy_extra_secret_provider_objects : {
        for item in try(object.jmesPath, []) : tostring(item.objectAlias) => {
          key      = tostring(object.objectName)
          property = trimprefix(trimsuffix(tostring(try(item.path, item.objectAlias)), "\""), "\"")
        }
        if try(object.objectType, "secretsmanager") == "secretsmanager" && startswith(tostring(try(object.objectName, "")), "arn:")
      }
    ]...
  )
  legacy_extra_external_secrets = [
    for secret_object in local.legacy_extra_secret_objects : {
      name = secret_object.secretName
      spec = {
        refreshInterval = "1h"
        secretStoreRef = {
          name = "zipline-secret-store"
          kind = "SecretStore"
        }
        target = {
          name           = secret_object.secretName
          creationPolicy = "Owner"
          template = {
            type = try(secret_object.type, "Opaque")
          }
        }
        data = [
          for item in try(secret_object.data, []) : {
            secretKey = item.key
            remoteRef = try(
              local.legacy_secret_provider_alias_refs[item.objectName],
              {
                key      = item.objectName
                property = item.objectName
              }
            )
          }
        ]
      }
    }
  ]
  extra_external_secrets = concat(
    try(local.cloud_args.extra_external_secrets, []),
    local.legacy_extra_external_secrets,
    local.redis.enabled && local.redis_password_secret_arn != "" ? [{
      name = "redis-credentials"
      spec = {
        refreshInterval = "1h"
        secretStoreRef  = { name = "zipline-secret-store", kind = "SecretStore" }
        target = {
          name           = "redis-credentials"
          creationPolicy = "Owner"
          template       = { type = "Opaque" }
        }
        data = [{
          secretKey = "REDIS_PASSWORD"
          remoteRef = {
            key      = local.redis_password_secret_arn
            property = local.redis.password_secret_key
          }
        }]
      }
    }] : [],
  )
  extra_external_secret_arns = distinct(compact(concat(
    try(local.cloud_args.extra_secret_arns, []),
    local.redis.enabled && local.redis_password_secret_arn != "" ? [local.redis_password_secret_arn] : [],
    flatten([
      for external_secret in local.extra_external_secrets : [
        for item in try(external_secret.spec.data, []) : tostring(try(item.remoteRef.key, ""))
        if startswith(tostring(try(item.remoteRef.key, "")), "arn:")
      ]
    ]),
  )))

  module_orchestration = merge(var.orchestration, {
    extra_secret_objects = []
    secrets = merge(try(var.orchestration.secrets, {}), {
      extra_secret_objects = []
    })
  })

  provider_context = {
    database = {
      host = aws_db_instance.zipline.address
      port = aws_db_instance.zipline.port
      name = local.cloud_args.database_name
    }
    prometheus = {
      query_endpoint = local.amp_query_endpoint
    }
    metrics_provider = "aws"
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
      { name = "AWS_REGION", value = local.cloud_args.region },
      { name = "AWS_DEFAULT_REGION", value = local.cloud_args.region },
    ]
    fetcher_env = concat([
      { name = "PROVIDER", value = "AWS" },
      { name = "KV_TABLE_PREFIX", value = local.cloud_args.kv_table_prefix },
      { name = "KV_ENABLE_TTL", value = tostring(local.cloud_args.kv_enable_ttl) },
      { name = "KV_REPLICA_REGIONS", value = join(",", local.cloud_args.kv_replica_regions) },
      { name = "CHRONON_METRICS_READER", value = "prometheus" },
      { name = "KV_STORE_TYPE", value = local.redis.enabled ? "redis" : "dynamodb" },
      ], local.redis.enabled ? [
      { name = "REDIS_CLUSTER_NODES", value = local.redis_cluster_nodes },
      { name = "REDIS_USE_SSL", value = tostring(local.redis.use_ssl) },
      ] : [], local.redis_password_secret_arn != "" ? [{
        name      = "REDIS_PASSWORD"
        valueFrom = { secretKeyRef = { name = "redis-credentials", key = "REDIS_PASSWORD" } }
      }] : [], [
      { name = "AWS_STS_REGIONAL_ENDPOINTS", value = "regional" },
    ])
    hub_env = concat(
      local.redis.enabled ? [
        { name = "KV_STORE_TYPE", value = "redis" },
        { name = "REDIS_CLUSTER_NODES", value = local.redis_cluster_nodes },
        { name = "REDIS_USE_SSL", value = tostring(local.redis.use_ssl) },
      ] : (local.cloud_args.kv_table_prefix == "" ? [] : [{ name = "KV_TABLE_PREFIX", value = local.cloud_args.kv_table_prefix }]),
      local.redis.enabled || local.cloud_args.kv_enable_ttl ? [] : [{ name = "KV_ENABLE_TTL", value = tostring(local.cloud_args.kv_enable_ttl) }],
      local.redis.enabled ? [] : (length(local.cloud_args.kv_replica_regions) == 0 ? [] : [{ name = "KV_REPLICA_REGIONS", value = join(",", local.cloud_args.kv_replica_regions) }]),
      local.redis.enabled ? [] : (local.cloud_args.kv_batch_table_gc_age_days == "" ? [] : [{ name = "KV_BATCH_TABLE_GC_AGE_DAYS", value = local.cloud_args.kv_batch_table_gc_age_days }]),
      local.redis_password_secret_arn != "" ? [{ name = "REDIS_PASSWORD", valueFrom = { secretKeyRef = { name = "redis-credentials", key = "REDIS_PASSWORD" } } }] : [],
      # Cluster name drives the AWS-console deployment URL emitted by
      # CrucibleSubmitter.getJobUrl. Without it the per-step "open in
      # console" link on each job comes up empty.
      [{ name = "EKS_CLUSTER_NAME", value = local.cluster_name }],
      # Databricks vault URI refs — giga tile / batch Iceberg jobs resolve these
      # at startup; the hub fills {NAME} placeholders without holding the secrets.
      try(trimspace(local.cloud_args.databricks_client_id), "") == "" ? [] : [
        { name = "DATABRICKS_CLIENT_ID", value = local.cloud_args.databricks_client_id },
        { name = "DATABRICKS_CLIENT_SECRET_VAULT_URI", value = aws_secretsmanager_secret.databricks_client_secret[0].arn },
        { name = "DATABRICKS_CREDENTIAL_VAULT_URI", value = aws_secretsmanager_secret.databricks_credential[0].arn },
      ],
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
    values = merge(
      local.provider_values,
      try(var.orchestration.values, {}),
      {
        orchestration = merge(
          try(local.provider_values.orchestration, {}),
          try(var.orchestration.values.orchestration, {}),
          {
            fetcher = merge(
              try(local.provider_values.orchestration.fetcher, {}),
              try(var.orchestration.values.orchestration.fetcher, {}),
            )
          }
        )
      }
    )
  }

  spark_event_log_dir = try(var.orchestration.compute.spark_event_log_dir, "") != "" ? var.orchestration.compute.spark_event_log_dir : "s3a://${local.cloud_args.warehouse_bucket}/spark-events"
  spark_history_opts = [
    "-Dspark.hadoop.fs.s3a.aws.credentials.provider=com.amazonaws.auth.WebIdentityTokenCredentialsProvider",
    "-Dspark.hadoop.fs.s3a.connection.maximum=200",
    "-Dspark.hadoop.fs.s3a.threads.max=50",
  ]
  hub_image                   = "ziplineai/hub-aws"
  eval_image                  = "ziplineai/eval-aws"
  hub_verticle_class          = "ai.chronon.hub.AWSOrchestrationVerticle,ai.chronon.hub.AWSWorkflowExecutionVerticle,ai.chronon.hub.cleanup.AWSCleanupVerticle"
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
  amp_workspace_id     = split("/", local.amp_workspace_arn)[1]
  amp_query_endpoint   = local.cloud_args.amp_workspace_arn != "" ? "https://aps-workspaces.${local.cloud_args.region}.${data.aws_partition.current.dns_suffix}/workspaces/${local.amp_workspace_id}" : trimsuffix(aws_prometheus_workspace.main.prometheus_endpoint, "/")
  hub_metrics_reader   = try(var.orchestration.hub.chronon_metrics_reader, try(var.orchestration.hub.metricsReader, "prometheus"))
  hub_metrics_port     = try(var.orchestration.hub.metrics_port, try(var.orchestration.hub.metricsPort, 8905))
  hub_prometheus_pod_annotations = local.hub_metrics_reader == "prometheus" ? {
    "prometheus.io/scrape" = "true"
    "prometheus.io/port"   = tostring(local.hub_metrics_port)
    "prometheus.io/path"   = "/metrics"
  } : {}
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
    externalTrafficPolicy = local.cloud_args.ingress_traffic_policy
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type"    = "nlb"
      "service.beta.kubernetes.io/aws-load-balancer-scheme"  = "internet-facing"
      "service.beta.kubernetes.io/aws-load-balancer-subnets" = join(",", [local.resolved_primary_subnet_id, local.resolved_secondary_subnet_id])
    }
  }

  provider_values = {
    # Shared-data StarRocks stores durable data in S3; FE and CN PVCs hold only
    # FE metadata and CN cache. Its Pods use the orchestration IRSA role, which
    # already has read/write access to the warehouse bucket.
    starrocks = {
      persistence = {
        storageClass = kubernetes_storage_class_v1.gp3.metadata[0].name
      }
      feConfig = {
        run_mode                            = "shared_data"
        cloud_native_storage_type           = "S3"
        aws_s3_path                         = "${local.cloud_args.warehouse_bucket}/dataexplorer"
        aws_s3_region                       = local.cloud_args.region
        aws_s3_use_aws_sdk_default_behavior = true
        aws_s3_use_instance_profile         = true
        enable_load_volume_from_conf        = true
      }
      awsGlueCatalog = {
        enabled = true
        name    = "aws_glue"
        region  = local.cloud_args.region
      }
      serviceAccount = local.orchestration_service_account
      nodeSelector   = local.system_node_selector
      tolerations    = local.system_node_tolerations
    }

    polaris = {
      nodeSelector = local.system_node_selector
      tolerations  = local.system_node_tolerations
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
      spotExecutors = true
      historyServer = {
        nodeSelector = local.system_node_selector
        tolerations  = local.system_node_tolerations
        persistence = {
          storageClass = kubernetes_storage_class_v1.gp3.metadata[0].name
        }
      }
      loki = {
        nodeSelector = local.system_node_selector
        tolerations  = local.system_node_tolerations
        storage = {
          storageClass = kubernetes_storage_class_v1.gp3.metadata[0].name
        }
      }
      imagePrepull = {
        nodeSelector = local.image_prepull_node_selector
        tolerations  = local.image_prepull_node_tolerations
        affinity     = local.image_prepull_affinity
      }
      warmPool = local.compute_warm_pool
    }

    orchestration = {
      hub = {
        nodeSelector = local.system_node_selector
        tolerations  = local.system_node_tolerations
      }
      ui = {
        nodeSelector = local.system_node_selector
        tolerations  = local.system_node_tolerations
      }
      fetcher = {
        nodeSelector = local.system_node_selector
        tolerations  = local.system_node_tolerations
      }
      eval = {
        nodeSelector = local.system_node_selector
        tolerations  = local.system_node_tolerations
      }
    }

    "ingress-nginx-ui" = {
      controller = {
        nodeSelector = merge({
          "kubernetes.io/os" = "linux"
        }, local.system_node_selector)
        tolerations = local.system_node_tolerations
        service     = local.ingress_lb_service
        admissionWebhooks = {
          patch = {
            nodeSelector = merge({
              "kubernetes.io/os" = "linux"
            }, local.system_node_selector)
            tolerations = local.system_node_tolerations
          }
        }
      }
    }

    "spark-operator" = {
      hook = {
        nodeSelector = local.system_node_selector
        tolerations  = local.system_node_tolerations
      }
      controller = {
        nodeSelector = local.system_node_selector
        tolerations  = local.system_node_tolerations
      }
    }
  }
}
