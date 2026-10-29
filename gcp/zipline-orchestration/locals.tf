locals {
  cloud_args = merge({
    # Required (no default): project_id, region, warehouse_bucket.
    cluster_name                        = ""
    network                             = ""
    subnet                              = ""
    node_cidr                           = ""
    pods_cidr                           = ""
    services_cidr                       = ""
    enable_private_nodes                = false
    enable_private_endpoint             = false
    master_ipv4_cidr_block              = "172.16.0.0/28"
    authorized_networks                 = []
    gke_release_channel                 = "regular"
    maintenance_window                  = "Saturday 02:00-06:00"
    system_machine_type                 = "n2-standard-16"
    compute_machine_type                = "c4a-standard-8"
    executor_machine_type               = "c4a-standard-8-lssd"
    autoscaling_profile                 = "OPTIMIZE_UTILIZATION"
    storage_class                       = "premium-rwo"
    logging_components                  = ["APISERVER", "CONTROLLER_MANAGER", "SCHEDULER", "SYSTEM_COMPONENTS", "WORKLOADS"]
    monitoring_components               = ["SYSTEM_COMPONENTS", "APISERVER", "SCHEDULER", "CONTROLLER_MANAGER", "STORAGE", "HPA", "POD", "DAEMONSET", "DEPLOYMENT", "STATEFULSET"]
    shared_warehouse_bucket             = ""
    additional_data_buckets             = []
    additional_flink_buckets            = []
    additional_flink_readonly_buckets   = []
    spark_libs_bucket                   = ""
    create_spark_libs_bucket            = false
    logs_bucket                         = ""
    artifact_repository                 = ""
    extra_secret_ids                    = []
    extra_external_secrets              = []
    auth_secret_id                      = ""
    personnel_emails                    = []
    cmek_key_id                         = ""
    ingress_load_balancer_ip            = ""
    ingress_traffic_policy              = "Cluster"
    gke_deletion_protection             = true
    bucket_force_destroy                = false
    # Cloud SQL knobs
    database_name                       = "execution_info"
    database_username                   = "locker_user"
    database_version                    = "POSTGRES_16"
    cloudsql_tier                       = "db-custom-2-4096"
    cloudsql_availability_type          = "REGIONAL"
    cloudsql_edition                    = "ENTERPRISE"
    cloudsql_disk_size                  = 20
    cloudsql_disk_autoresize_limit      = 100
    cloudsql_max_connections            = 300
    cloudsql_backup_retention_days      = 7
    cloudsql_query_insights             = false
    database_deletion_protection        = true
    database_create_final_backup        = true
    database_deny_maintenance_start_date = "2026-01-01"
    database_deny_maintenance_end_date   = "2026-01-14"
    # Bigtable knobs
    bigtable_instance                   = ""
    bigtable_zone                       = ""
    bigtable_min_nodes                  = 1
    bigtable_max_nodes                  = 10
    bigtable_cpu_target                 = 60
    bigtable_storage_target_gib         = 2560
    bigtable_deletion_protection        = true
    secret_deletion_protection          = true
    # DNS / Cloudflare (optional)
    cloudflare_record_name              = ""
  }, var.gcp)

  install                       = try(var.orchestration.install, {})
  deployment                    = var.orchestration.deployment
  deploy_fetcher                = try(local.deployment.deploy_fetcher, false)
  name_prefix                   = local.deployment.customer_name
  orchestration_namespace       = try(local.install.namespace, "zipline-system")
  orchestration_service_account = try(var.orchestration.service_account.name, "orchestration-sa")
  compute_namespace_prefix      = try(local.cloud_args.compute_namespace_prefix, "zipline-")
  spark_service_account         = try(var.orchestration.compute.spark_service_account, "spark-operator-spark")
  flink_service_account         = try(var.orchestration.compute.flink_service_account, "flink")

  compute_namespaces = try(var.orchestration.compute.namespaces, [{ name = try(var.orchestration.compute.default_namespace, "zipline-default"), team = "default" }])

  bigtable_zone = local.cloud_args.bigtable_zone != "" ? local.cloud_args.bigtable_zone : "${local.cloud_args.region}-a"
  bigtable_instance_name = local.cloud_args.bigtable_instance != "" ? local.cloud_args.bigtable_instance : "zipline-${local.name_prefix}-instance"

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
  # Prefer gcp.auth_secret_id, fall back to orchestration.auth.secrets_arn
  # (named "arn" for AWS parity in the shared schema; it's a Secret Manager
  # id here).
  auth_secret_id = try(coalesce(
    try(local.cloud_args.auth_secret_id, ""),
    try(var.orchestration.auth.secrets_arn, ""),
  ), "")

  hub_image           = "ziplineai/hub-gcp"
  eval_image          = "ziplineai/eval-gcp"
  hub_verticle_class  = "ai.chronon.hub.GCPOrchestrationVerticle,ai.chronon.hub.GCPWorkflowExecutionVerticle,ai.chronon.hub.cleanup.GCPCleanupVerticle"
  spark_event_log_dir = try(var.orchestration.compute.spark_event_log_dir, "") != "" ? var.orchestration.compute.spark_event_log_dir : "gs://${local.cloud_args.warehouse_bucket}/spark-events"

  # Flink jar base path (§3.4, §9.4). Mandatory; empty =>
  # resolvedAdditionalJarUris drops bare filenames and Flink runs with no jars.
  flink_jars_base_path = try(coalesce(
    try(local.cloud_args.flink_jars_base_path, ""),
    "gs://${local.spark_libs_bucket_name}/spark-4.1.3/libs/",
  ), "")

  polaris_base_location      = "gs://${local.cloud_args.warehouse_bucket}/polaris/polaris_${local.name_prefix}/"
  polaris_client_secret_name = "polaris-client-credentials"
  polaris_client_secret_key  = "OC_CREDENTIAL"

  hub_metrics_reader   = try(var.orchestration.hub.chronon_metrics_reader, try(var.orchestration.hub.metricsReader, "prometheus"))
  hub_metrics_port     = try(var.orchestration.hub.metrics_port, try(var.orchestration.hub.metricsPort, 8905))
  hub_prometheus_pod_annotations = local.hub_metrics_reader == "prometheus" ? {
    "prometheus.io/scrape" = "true"
    "prometheus.io/port"   = tostring(local.hub_metrics_port)
    "prometheus.io/path"   = "/metrics"
  } : {}

  module_orchestration = merge(var.orchestration, {
    extra_secret_objects = []
    secrets = merge(try(var.orchestration.secrets, {}), {
      extra_secret_objects = []
    })
  })

  # Wrapper-side addon defaults. Module merge order is
  # `merge(orchestration_addons, provider_context.addons)` — provider_context
  # wins. Each entry below is only set when the tfvars hasn't already provided
  # its own override, so a stack can still override from tfvars.
  #
  # - install_metrics_server: GKE Standard ships metrics-server as a system
  #   addon; chart addon would clobber it (§10.6).
  # - kuberay_operator_values.priorityClassName: the shared addons module
  #   defaults kuberay to priorityClassName=system-cluster-critical. GKE's
  #   admission controller only allows system-* priority classes in
  #   kube-system, so installing kuberay in zipline-system fails with
  #   "insufficient quota to match these scopes". Clear it.
  # - external_secrets_operator_values.serviceAccount.annotations: the ESO
  #   chart creates its own KSA, which Terraform's identity.tf separately
  #   binds to the eso GSA via Workload Identity. The KSA needs the
  #   iam.gke.io/gcp-service-account annotation for that binding to resolve.
  provider_addons = merge(
    try(var.orchestration.addons.install_metrics_server, null) == null ? { install_metrics_server = false } : {},
    try(var.orchestration.addons.external_secrets_operator_values, null) == null ? {
      external_secrets_operator_values = {
        serviceAccount = {
          annotations = {
            "iam.gke.io/gcp-service-account" = google_service_account.external_secrets.email
          }
        }
      }
    } : {},
    try(var.orchestration.addons.kuberay_operator_values, null) == null ? {
      kuberay_operator_values = {
        priorityClassName = ""
      }
    } : {},
  )

  # §3.4 runtime contract. Hub pod env emitted via provider_hub_env.
  hub_env = concat(
    [
      { name = "GCP_PROJECT_ID", value = local.cloud_args.project_id },
      { name = "GCP_BIGTABLE_INSTANCE_ID", value = local.bigtable_instance_name },
      { name = "CRUCIBLE_FLINK_JARS_BASE_PATH", value = local.flink_jars_base_path },
      { name = "LOG_PROVIDER", value = "gcp" },
    ],
    [{
      name = "OC_CREDENTIAL"
      valueFrom = {
        secretKeyRef = {
          name     = local.polaris_client_secret_name
          key      = local.polaris_client_secret_key
          optional = true
        }
      }
    }],
  )

  # Eval reads project-id so BigQuery SDK/jobs resolve the current project
  # without extra config.
  eval_env = [
    { name = "GCP_PROJECT_ID", value = local.cloud_args.project_id },
  ]

  # UI knob (§11): the UI *queries* Managed Prometheus; the hub stays on
  # Prometheus-style metrics (§3.4). Do not set CHRONON_METRICS_READER=gcp.
  ui_env = [
    { name = "METRICS_PROVIDER", value = "gcp" },
    { name = "LOG_PROVIDER", value = "gcp" },
  ]

  # Every service gets runtime_env, so GOOGLE_CLOUD_PROJECT is set here only.
  runtime_env = [
    { name = "GOOGLE_CLOUD_PROJECT", value = local.cloud_args.project_id },
  ]

  fetcher_env = [
    { name = "PROVIDER", value = "GCP" },
    { name = "GCP_PROJECT_ID", value = local.cloud_args.project_id },
    { name = "GCP_BIGTABLE_INSTANCE_ID", value = local.bigtable_instance_name },
    { name = "CHRONON_METRICS_READER", value = "prometheus" },
    { name = "KV_STORE_TYPE", value = "bigtable" },
  ]

  provider_context = {
    addons = local.provider_addons
    database = {
      host = google_sql_database_instance.zipline.private_ip_address
      port = 5432
      name = local.cloud_args.database_name
    }
    prometheus = {
      # Managed Prometheus query endpoint used by the UI
      # (frontend/src/lib/server/metricsProvider.ts querying
      # monitoring.googleapis.com). Project-scoped, so the location is
      # `global` by convention.
      query_endpoint = "https://monitoring.googleapis.com/v1/projects/${local.cloud_args.project_id}/location/global/prometheus"
    }
    metrics_provider = "gcp"
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
      spark_event_log_dir = local.spark_event_log_dir
      # Spark on GCP uses Workload Identity + ADC + the Spark image's bundled
      # GoogleHadoopFileSystem — no fs.gs.auth.* keys, no key files.
      history_server_options = []
      service_account = {
        annotations = {
          "iam.gke.io/gcp-service-account" = google_service_account.spark.email
        }
      }
      flink_defaults = {
        serviceAccountAnnotations = {
          "iam.gke.io/gcp-service-account" = google_service_account.flink.email
        }
      }
    }
    service_account_annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.orchestration.email
    }
    secrets = {
      secret_store = {
        create = true
        name   = "zipline-secret-store"
        kind   = "ClusterSecretStore"
        spec = {
          provider = {
            gcpsm = {
              projectID = local.cloud_args.project_id
              auth = {
                workloadIdentity = {
                  clusterLocation   = local.cloud_args.region
                  clusterName       = local.cluster_name
                  clusterProjectID  = local.cloud_args.project_id
                  serviceAccountRef = {
                    name      = "external-secrets"
                    namespace = local.orchestration_namespace
                  }
                }
              }
            }
          }
        }
      }
      database_remote_refs = {
        username = {
          key      = google_secret_manager_secret.db_credentials.secret_id
          property = "username"
        }
        password = {
          key      = google_secret_manager_secret.db_credentials.secret_id
          property = "password"
        }
      }
      auth_remote_refs = {
        for key in local.auth_secret_keys : key => {
          key      = local.auth_secret_id
          property = key
        }
      }
      extra_external_secrets = try(local.cloud_args.extra_external_secrets, [])
    }
    runtime_env = local.runtime_env
    hub_env     = local.hub_env
    eval_env    = local.eval_env
    ui_env      = local.ui_env
    fetcher_env = local.fetcher_env
    values      = local.provider_values
  }

  provider_values = {
    starrocks = {
      persistence = {
        storageClass = local.cloud_args.storage_class
      }
      # §9.5: StarRocks reaches GCS over the S3 XML interop API, authenticated
      # by HMAC keys. The HMAC key material lives in state + in the SR CR
      # (R11); keep the bucket-scoped GSA so rotation is a bounded blast.
      feConfig = {
        run_mode                            = "shared_data"
        cloud_native_storage_type           = "S3"
        aws_s3_path                         = "${local.cloud_args.warehouse_bucket}/dataexplorer"
        aws_s3_region                       = local.cloud_args.region
        aws_s3_endpoint                     = "https://storage.googleapis.com"
        aws_s3_use_aws_sdk_default_behavior = false
        aws_s3_use_instance_profile         = false
        enable_load_volume_from_conf        = true
      }
      awsGlueCatalog = {
        enabled = false
      }
      serviceAccount = local.orchestration_service_account
      nodeSelector   = local.system_node_selector
      tolerations    = local.system_node_tolerations
    }

    polaris = {
      nodeSelector = local.system_node_selector
      tolerations  = local.system_node_tolerations
      bootstrap = {
        runtimeClient = {
          credentialsSecret = {
            name = local.polaris_client_secret_name
            key  = local.polaris_client_secret_key
          }
        }
        rbac = {
          catalog = {
            # The chart derives a bucket-relative path from compute.objectStore
            # (bare name). Override to a scheme-prefixed URI so GCS catalogs
            # resolve. Mirrors AWS override (aws/.../locals.tf:484,589).
            defaultBaseLocation = local.polaris_base_location
            storage = {
              type             = "GCS"
              allowedLocations = [local.polaris_base_location]
              config = {
                gcsServiceAccount = "serviceAccount:${google_service_account.polaris_storage.email}"
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
          storageClass = local.cloud_args.storage_class
        }
      }
      loki = {
        nodeSelector = local.system_node_selector
        tolerations  = local.system_node_tolerations
        storage = {
          storageClass = local.cloud_args.storage_class
        }
      }
      imagePrepull = {
        nodeSelector = local.image_prepull_node_selector
        tolerations  = local.image_prepull_node_tolerations
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
        nodeSelector = merge({ "kubernetes.io/os" = "linux" }, local.system_node_selector)
        tolerations  = local.system_node_tolerations
        service      = local.ingress_lb_service
        admissionWebhooks = {
          patch = {
            nodeSelector = merge({ "kubernetes.io/os" = "linux" }, local.system_node_selector)
            tolerations  = local.system_node_tolerations
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
