locals {
  cloud_args = merge({
    cluster_name                   = ""
    eks_version                    = "1.36"
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

  # When no VPC is supplied, provision one (network.tf) and resolve ids here.
  # Kept out of cloud_args: the aws provider reads cloud_args.region, so folding
  # these resource refs into cloud_args would cycle provider -> network -> provider.
  create_network               = trimspace(tostring(try(var.aws.vpc_id, ""))) == ""
  resolved_vpc_id              = local.create_network ? aws_vpc.main[0].id : trimspace(tostring(try(var.aws.vpc_id, "")))
  resolved_primary_subnet_id   = local.create_network ? aws_subnet.zipline["primary"].id : trimspace(tostring(try(var.aws.primary_subnet_id, "")))
  resolved_secondary_subnet_id = local.create_network ? aws_subnet.zipline["secondary"].id : trimspace(tostring(try(var.aws.secondary_subnet_id, "")))

  install                       = try(var.orchestration.install, {})
  deployment                    = var.orchestration.deployment
  name_prefix                   = local.deployment.customer_name
  cluster_name                  = local.cloud_args.cluster_name != "" ? local.cloud_args.cluster_name : "${local.name_prefix}-eks"
  orchestration_namespace       = try(local.install.namespace, "zipline-system")
  orchestration_service_account = try(var.orchestration.service_account.name, "orchestration-sa")
  compute_namespace_prefix      = try(local.cloud_args.compute_namespace_prefix, "zipline-")
  spark_service_account         = try(var.orchestration.compute.spark_service_account, "spark-operator-spark")
  flink_service_account         = try(var.orchestration.compute.flink_service_account, "flink")

  compute_namespaces        = try(var.orchestration.compute.namespaces, [{ name = try(var.orchestration.compute.default_namespace, "zipline-default"), team = "default" }])
  compute_teams             = distinct([for namespace in local.compute_namespaces : try(tostring(namespace.team), "default")])
  default_compute_namespace = try(var.orchestration.compute.default_namespace, try(local.compute_namespaces[0].name, "zipline-default"))
  default_compute_team = try(
    [for namespace in local.compute_namespaces : tostring(namespace.team) if try(namespace.name, "") == local.default_compute_namespace][0],
    try(tostring(local.compute_namespaces[0].team), "default"),
  )
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
  compute_team_slug_bases = {
    for team in local.compute_teams :
    team => trim(replace(replace(lower(trimspace(team)), "/[^a-z0-9-]/", "-"), "/-+/", "-"), "-")
  }
  compute_team_slugs = {
    for team, slug in local.compute_team_slug_bases :
    team => (
      slug == "" ? "default" :
      length(slug) <= 63 ? slug :
      "${trimsuffix(substr(slug, 0, 54), "-")}-${substr(sha1(slug), 0, 8)}"
    )
  }
  compute_node_pool_workloads = [
    { engine = "spark", role = "driver", size = "driver" },
    { engine = "spark", role = "executor", size = "executor" },
    { engine = "flink", role = "jobmanager", size = "driver" },
    { engine = "flink", role = "taskmanager", size = "executor" },
  ]
  compute_node_pool_pairs = [
    for workload in local.compute_node_pool_workloads : {
      team      = "default"
      engine    = workload.engine
      role      = workload.role
      size      = workload.size
      node_pool = "default-${workload.engine}-${workload.role}"
    }
  ]
  compute_node_pool_slugs = {
    for pool in local.compute_node_pool_pairs :
    "${pool.team}:${pool.engine}:${pool.role}" => (
      length(pool.node_pool) <= 63 ? pool.node_pool :
      "${trimsuffix(substr(pool.node_pool, 0, 54), "-")}-${substr(sha1(pool.node_pool), 0, 8)}"
    )
  }
  default_compute_team_slug = try(local.compute_team_slugs[local.default_compute_team], "default")
  system_node_pool          = "system"
  image_prepull_node_pool   = local.compute_node_pool_slugs["default:spark:executor"]
  system_node_selector = local.karpenter.enabled ? {
    "zipline.ai/node-pool" = local.system_node_pool
  } : {}
  image_prepull_node_selector = local.karpenter.enabled ? {
    "zipline.ai/team"   = "default"
    "zipline.ai/engine" = "spark"
    "zipline.ai/role"   = "executor"
  } : {}
  system_node_tolerations = local.karpenter.enabled ? [
    {
      key      = "zipline.ai/node-pool"
      operator = "Equal"
      value    = local.system_node_pool
      effect   = "NoSchedule"
    }
  ] : []
  image_prepull_node_tolerations = local.karpenter.enabled ? [
    {
      key      = "zipline.ai/workload"
      operator = "Equal"
      value    = local.image_prepull_node_pool
      effect   = "NoSchedule"
    }
  ] : []
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
  karpenter_node_pool_requirements = [
    {
      key      = "kubernetes.io/os"
      operator = "In"
      values   = ["linux"]
    },
    {
      key      = "kubernetes.io/arch"
      operator = "In"
      values   = ["amd64"]
    },
    {
      key      = "karpenter.sh/capacity-type"
      operator = "In"
      values   = ["on-demand"]
    },
    {
      key      = "karpenter.k8s.aws/instance-category"
      operator = "In"
      values   = ["c", "m", "r"]
    },
    {
      key      = "karpenter.k8s.aws/instance-generation"
      operator = "Gt"
      values   = ["2"]
    },
  ]
  # ───────────────────────────────────────────────────────────────────────
  # Karpenter tunables — override any of these via aws.karpenter.<key> in the
  # tfvars. All optional; the defaults shown here apply when unset. The
  # instance-shape knobs (arch / categories / capacity / generation / minValues)
  # build the driver & executor pool requirements below.
  #   aws.karpenter.driver_arch              (default ["arm64"])
  #   aws.karpenter.driver_categories        (default ["m"])
  #   aws.karpenter.executor_arch            (default ["arm64"])
  #   aws.karpenter.executor_categories      (default ["c","m","r"])
  #   aws.karpenter.executor_capacity_type   (default ["spot"])
  #   aws.karpenter.executor_min_categories  (default 2)     # spot diversity
  #   aws.karpenter.min_instance_generation  (default "6")   # 7th-gen+
  #   aws.karpenter.pool_limits/driver_limits/executor_limits  ({cpu,memory})
  #   aws.karpenter.system_expire_after / compute_expire_after
  #   aws.karpenter.system_termination_grace_period
  # ───────────────────────────────────────────────────────────────────────
  karpenter_driver_arch         = tolist(try(local.karpenter.driver_arch, ["arm64"]))
  karpenter_driver_categories   = tolist(try(local.karpenter.driver_categories, ["m"]))
  karpenter_executor_arch       = tolist(try(local.karpenter.executor_arch, ["arm64"]))
  karpenter_executor_categories = tolist(try(local.karpenter.executor_categories, ["c", "m", "r"]))
  karpenter_executor_capacity   = tolist(try(local.karpenter.executor_capacity_type, ["spot"]))
  karpenter_executor_min_values = try(local.karpenter.executor_min_categories, 2)
  karpenter_min_generation      = try(local.karpenter.min_instance_generation, "6")
  # Provisioning caps (max aggregate a pool may launch); memory cap alongside
  # cpu so a runaway pool can't exhaust either. Role-sized: drivers small,
  # executors fat.
  karpenter_pool_limits     = merge({ cpu = "1000", memory = "4000Gi" }, try(local.karpenter.pool_limits, {}))
  karpenter_driver_limits   = merge({ cpu = "100", memory = "400Gi" }, try(local.karpenter.driver_limits, {}))
  karpenter_executor_limits = merge({ cpu = "1000", memory = "4000Gi" }, try(local.karpenter.executor_limits, {}))
  # Driver pool: on-demand — drivers are lightweight (1/job) and must NOT run on
  # spot (a spot eviction kills the whole job).
  karpenter_driver_requirements = [
    { key = "kubernetes.io/os", operator = "In", values = tolist(["linux"]) },
    { key = "kubernetes.io/arch", operator = "In", values = local.karpenter_driver_arch },
    { key = "karpenter.sh/capacity-type", operator = "In", values = tolist(["on-demand"]) },
    { key = "karpenter.k8s.aws/instance-category", operator = "In", values = local.karpenter_driver_categories, minValues = null },
    { key = "karpenter.k8s.aws/instance-generation", operator = "Gt", values = tolist([local.karpenter_min_generation]) },
  ]
  # Executor pool: spot by default — the compute; spot decommission migrates
  # shuffle. minValues forces instance-type diversity for spot availability.
  karpenter_executor_requirements = [
    { key = "kubernetes.io/os", operator = "In", values = tolist(["linux"]) },
    { key = "kubernetes.io/arch", operator = "In", values = local.karpenter_executor_arch },
    { key = "karpenter.sh/capacity-type", operator = "In", values = local.karpenter_executor_capacity },
    { key = "karpenter.k8s.aws/instance-category", operator = "In", values = local.karpenter_executor_categories, minValues = local.karpenter_executor_min_values },
    { key = "karpenter.k8s.aws/instance-generation", operator = "Gt", values = tolist([local.karpenter_min_generation]) },
  ]
  karpenter_spark_executor_instance_store_requirements = [
    { key = "karpenter.k8s.aws/instance-local-nvme", operator = "Exists", values = null, minValues = null },
  ]
  # The system pool hosts stateful control-plane pods (loki + spark-history
  # PVCs, polaris). Default to no forced node rotation and a real drain grace
  # period so a rotation doesn't strand a PVC in the wrong AZ or cut loki off
  # mid-flush. Compute pools keep the 30-day recycle. All configurable.
  karpenter_system_expire_after             = try(local.karpenter.system_expire_after, "Never")
  karpenter_system_termination_grace_period = try(local.karpenter.system_termination_grace_period, "5m")
  karpenter_compute_expire_after            = try(local.karpenter.compute_expire_after, "720h")
  compute_node_pool_matrix = [
    for pool in local.compute_node_pool_pairs : {
      key            = local.compute_node_pool_slugs["${pool.team}:${pool.engine}:${pool.role}"]
      team           = pool.team
      engine         = pool.engine
      role           = pool.role
      size           = pool.size
      node_pool      = local.compute_node_pool_slugs["${pool.team}:${pool.engine}:${pool.role}"]
      instance_store = pool.engine == "spark" && pool.role == "executor"
      taints = [
        {
          key      = "zipline.ai/workload"
          operator = "Equal"
          value    = local.compute_node_pool_slugs["${pool.team}:${pool.engine}:${pool.role}"]
          effect   = "NoSchedule"
        }
      ]
    }
  ]
  karpenter_system_node_pool = {
    system = {
      enabled = true
      name    = local.system_node_pool
      labels = {
        "zipline.ai/team"      = "system"
        "zipline.ai/node-pool" = local.system_node_pool
      }
      taints                 = local.system_node_tolerations
      requirements           = local.karpenter_node_pool_requirements
      expireAfter            = local.karpenter_system_expire_after
      terminationGracePeriod = local.karpenter_system_termination_grace_period
      limits                 = local.karpenter_pool_limits
      disruption = {
        # Only reclaim genuinely-empty nodes. WhenEmptyOrUnderutilized would
        # drain still-in-use nodes, disrupting running Spark executors / Flink
        # taskmanagers and stateful control-plane pods (loki, spark-history);
        # the platform submitter does not set karpenter.sh/do-not-disrupt.
        consolidationPolicy = "WhenEmpty"
        consolidateAfter    = "1m"
      }
    }
  }
  karpenter_compute_node_pools = {
    for pool in local.compute_node_pool_matrix :
    pool.key => {
      enabled = true
      name    = pool.node_pool
      labels = {
        "zipline.ai/team"     = pool.team
        "zipline.ai/engine"   = pool.engine
        "zipline.ai/role"     = pool.role
        "zipline.ai/workload" = pool.node_pool
      }
      taints = pool.taints
      requirements = concat(
        pool.size == "driver" ? local.karpenter_driver_requirements : local.karpenter_executor_requirements,
        pool.instance_store ? local.karpenter_spark_executor_instance_store_requirements : [],
      )
      expireAfter = local.karpenter_compute_expire_after
      limits      = pool.size == "driver" ? local.karpenter_driver_limits : local.karpenter_executor_limits
      disruption = {
        # Only reclaim genuinely-empty nodes. WhenEmptyOrUnderutilized would
        # drain still-in-use nodes, disrupting running Spark executors / Flink
        # taskmanagers and stateful control-plane pods (loki, spark-history);
        # the platform submitter does not set karpenter.sh/do-not-disrupt.
        consolidationPolicy = "WhenEmpty"
        consolidateAfter    = "1m"
      }
    }
  }
  karpenter_default_node_pools = merge(
    local.karpenter_system_node_pool,
    local.karpenter_compute_node_pools,
  )
  karpenter_node_pool_inputs = {
    for key, pool in merge(local.karpenter_default_node_pools, try(local.karpenter.node_pools, {})) :
    key => merge(try(local.karpenter_default_node_pools[key], {}), pool)
  }
  karpenter_node_pools = {
    for key, pool in local.karpenter_node_pool_inputs :
    key => pool
    if local.karpenter.enabled && try(pool.enabled, true)
  }

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
  configured_auth_secret_arn = trimspace(local.cloud_args.auth_secret_arn) != "" ? local.cloud_args.auth_secret_arn : try(var.orchestration.auth.secrets_arn, "")
  create_auth_secret         = local.auth_enabled && length(keys(local.cloud_args.auth_secret_values)) > 0
  auth_secret_arn            = local.create_auth_secret ? aws_secretsmanager_secret.zipline_auth[0].arn : local.configured_auth_secret_arn

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
  )
  extra_external_secret_arns = distinct(compact(concat(
    try(local.cloud_args.extra_secret_arns, []),
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
    hub_env = concat(
      local.cloud_args.kv_table_prefix == "" ? [] : [{ name = "KV_TABLE_PREFIX", value = local.cloud_args.kv_table_prefix }],
      local.cloud_args.kv_enable_ttl ? [] : [{ name = "KV_ENABLE_TTL", value = tostring(local.cloud_args.kv_enable_ttl) }],
      length(local.cloud_args.kv_replica_regions) == 0 ? [] : [{ name = "KV_REPLICA_REGIONS", value = join(",", local.cloud_args.kv_replica_regions) }],
      # Cluster name drives the AWS-console deployment URL emitted by
      # CrucibleSubmitter.getJobUrl. Without it the per-step "open in
      # console" link on each job comes up empty.
      [{ name = "EKS_CLUSTER_NAME", value = local.cluster_name }],
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
      }
      # Warm pool (driver-sized pause pods) pre-provisions a Spark driver node so
      # real drivers skip a cold Karpenter launch. Reuse the driver pool's own
      # labels/taints so the pause pods land there and can't drift from the pool.
      warmPool = {
        enabled      = local.karpenter.enabled
        nodeSelector = local.karpenter_compute_node_pools[local.compute_node_pool_slugs["default:spark:driver"]].labels
        tolerations  = local.karpenter_compute_node_pools[local.compute_node_pool_slugs["default:spark:driver"]].taints
      }
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
