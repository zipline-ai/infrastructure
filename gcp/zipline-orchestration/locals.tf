locals {
  cloud_args = merge({
    network                          = ""
    subnetwork                       = ""
    network_project_id               = ""
    network_cidr                     = "10.0.0.0/20"
    pods_range_name                  = "gke-pods"
    pods_range_cidr                  = "10.16.0.0/14"
    services_range_name              = "gke-services"
    services_range_cidr              = "10.20.0.0/20"
    private_nodes                    = true
    enable_private_endpoint          = true
    master_ipv4_cidr_block           = "172.16.0.0/28"
    master_authorized_networks       = []
    create_cloud_nat                 = true
    cluster_name                     = ""
    kubernetes_version               = null
    release_channel                  = "REGULAR"
    deletion_protection              = true
    system_node_pool                 = {}
    node_pools                       = {}
    bucket_location                  = ""
    logs_bucket                      = ""
    bucket_force_destroy             = false
    bucket_versioning_enabled        = true
    database_host                    = ""
    database_name                    = "execution_info"
    database_username                = "locker_user"
    database_instance_name           = ""
    database_credentials_secret_name = ""
    database_version                 = "POSTGRES_16"
    database_tier                    = "db-custom-2-7680"
    database_availability_type       = "REGIONAL"
    database_disk_size               = 20
    database_backup_enabled          = true
    database_deletion_protection     = true
    create_private_service_access    = null
    private_service_prefix_length    = 16
    secret_force_destroy             = false
    auth_secret_ids                  = {}
    auth_secret_values               = {}
    workload_roles                   = {}
  }, var.gcp)

  project_id         = trimspace(local.cloud_args.project_id)
  region             = trimspace(local.cloud_args.region)
  deployment         = var.orchestration.deployment
  install            = try(var.orchestration.install, {})
  name_prefix        = local.deployment.customer_name
  cluster_name       = local.cloud_args.cluster_name != "" ? local.cloud_args.cluster_name : "${local.name_prefix}-gke"
  network_name       = local.cloud_args.network != "" ? local.cloud_args.network : "${local.name_prefix}-gke-vpc"
  subnetwork_name    = local.cloud_args.subnetwork != "" ? local.cloud_args.subnetwork : "${local.name_prefix}-gke-subnet"
  network_project_id = local.cloud_args.network_project_id != "" ? local.cloud_args.network_project_id : local.project_id
  bucket_location    = local.cloud_args.bucket_location != "" ? local.cloud_args.bucket_location : local.region

  orchestration_namespace       = try(local.install.namespace, "zipline-system")
  orchestration_service_account = try(var.orchestration.service_account.name, "orchestration-sa")
  spark_service_account         = try(var.orchestration.compute.spark_service_account, "spark-operator-spark")
  flink_service_account         = try(var.orchestration.compute.flink_service_account, "flink")
  compute_namespaces = distinct([
    for namespace in try(var.orchestration.compute.namespaces, [{ name = "zipline-default", team = "default" }]) :
    namespace.name
  ])

  artifact_prefix_without_scheme   = trimprefix(trimspace(local.deployment.artifact_prefix), "gs://")
  artifact_bucket_name             = split("/", local.artifact_prefix_without_scheme)[0]
  warehouse_bucket_name            = split("/", trimsuffix(trimprefix(trimspace(local.cloud_args.warehouse_bucket), "gs://"), "/"))[0]
  logs_bucket_name                 = local.cloud_args.logs_bucket != "" ? split("/", trimsuffix(trimprefix(trimspace(local.cloud_args.logs_bucket), "gs://"), "/"))[0] : "${substr(local.project_id, 0, 20)}-zl-${substr(local.name_prefix, 0, 15)}-${substr(sha1("${local.project_id}:${local.name_prefix}"), 0, 8)}"
  database_name                    = local.cloud_args.database_name != "" ? local.cloud_args.database_name : try(var.orchestration.database.name, "execution_info")
  database_instance_name           = local.cloud_args.database_instance_name != "" ? local.cloud_args.database_instance_name : "${local.name_prefix}-zipline-orch-instance"
  database_credentials_secret_name = local.cloud_args.database_credentials_secret_name != "" ? local.cloud_args.database_credentials_secret_name : "${local.name_prefix}-postgres-credentials"
  database_host                    = local.cloud_args.database_host != "" ? local.cloud_args.database_host : google_sql_database_instance.main.private_ip_address
  create_private_service_access = (
    local.cloud_args.create_private_service_access != null
    ? local.cloud_args.create_private_service_access
    : local.create_network
  )

  required_services = toset([
    "artifactregistry.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "monitoring.googleapis.com",
    "secretmanager.googleapis.com",
    "servicenetworking.googleapis.com",
    "sqladmin.googleapis.com",
    "storage.googleapis.com",
  ])

  default_system_node_pool = {
    name               = "system"
    initial_node_count = 1
    min_node_count     = 3
    max_node_count     = 6
    machine_type       = "e2-standard-8"
    disk_type          = "pd-balanced"
    disk_size_gb       = 128
    image_type         = "COS_CONTAINERD"
    spot               = false
    labels = {
      "zipline.ai/node-pool" = "system"
    }
    taints = []
  }
  system_node_pool = merge(local.default_system_node_pool, local.cloud_args.system_node_pool, {
    labels = merge(local.default_system_node_pool.labels, try(local.cloud_args.system_node_pool.labels, {}))
    taints = try(local.cloud_args.system_node_pool.taints, local.default_system_node_pool.taints)
  })

  workload_service_accounts = {
    orchestration = {
      account_id = "${substr(local.name_prefix, 0, 15)}-orch-${substr(sha1(local.name_prefix), 0, 8)}"
      kubernetes_service_accounts = [
        "${local.orchestration_namespace}/${local.orchestration_service_account}",
      ]
      roles = distinct(concat([
        "roles/cloudsql.client",
        "roles/logging.logWriter",
        "roles/monitoring.metricWriter",
      ], try(local.cloud_args.workload_roles.orchestration, [])))
    }
    spark = {
      account_id = "${substr(local.name_prefix, 0, 15)}-sp-${substr(sha1(local.name_prefix), 0, 8)}"
      kubernetes_service_accounts = [
        for namespace in local.compute_namespaces : "${namespace}/${local.spark_service_account}"
      ]
      roles = distinct(concat([
        "roles/logging.logWriter",
        "roles/monitoring.metricWriter",
      ], try(local.cloud_args.workload_roles.spark, [])))
    }
    flink = {
      account_id = "${substr(local.name_prefix, 0, 15)}-fl-${substr(sha1(local.name_prefix), 0, 8)}"
      kubernetes_service_accounts = [
        for namespace in local.compute_namespaces : "${namespace}/${local.flink_service_account}"
      ]
      roles = distinct(concat([
        "roles/logging.logWriter",
        "roles/monitoring.metricWriter",
      ], try(local.cloud_args.workload_roles.flink, [])))
    }
  }

  auth_enabled      = try(var.orchestration.auth.enabled, false)
  auth_saml_enabled = try(var.orchestration.auth.sso_use_saml, false)
  auth_secret_keys = concat([
    "auth-secret",
    "google-oauth-client-secret",
    "github-oauth-client-secret",
    "microsoft-entra-oauth-client-secret",
    "sso-client-secret",
  ], local.auth_saml_enabled ? ["sso-saml-cert"] : [])
  created_auth_secret_ids = {
    for key in keys(local.cloud_args.auth_secret_values) :
    replace(key, "_", "-") => "${local.name_prefix}-${replace(key, "_", "-")}"
  }
  configured_auth_secret_ids = merge(local.cloud_args.auth_secret_ids, local.created_auth_secret_ids)

  workload_annotations = {
    orchestration = {
      "iam.gke.io/gcp-service-account" = google_service_account.workload["orchestration"].email
    }
    spark = {
      "iam.gke.io/gcp-service-account" = google_service_account.workload["spark"].email
    }
    flink = {
      "iam.gke.io/gcp-service-account" = google_service_account.workload["flink"].email
    }
  }

  spark_event_log_dir       = try(var.orchestration.compute.spark_event_log_dir, "") != "" ? var.orchestration.compute.spark_event_log_dir : "gs://${local.warehouse_bucket_name}/spark-events"
  polaris_base_location     = "gs://${local.warehouse_bucket_name}/polaris/polaris_${local.name_prefix}/"
  prometheus_query_endpoint = "https://monitoring.googleapis.com/v1/projects/${local.project_id}/location/global/prometheus/api/v1"
  hub_image                 = "ziplineai/hub-gcp"
  eval_image                = "ziplineai/eval-gcp"
  hub_verticle_class        = "ai.chronon.hub.GCPOrchestrationVerticle,ai.chronon.hub.GCPWorkflowExecutionVerticle"
  hub_metrics_reader        = try(var.orchestration.hub.chronon_metrics_reader, try(var.orchestration.hub.metricsReader, "prometheus"))
  hub_metrics_port          = try(var.orchestration.hub.metrics_port, try(var.orchestration.hub.metricsPort, 8905))
  hub_prometheus_pod_annotations = local.hub_metrics_reader == "prometheus" ? {
    "prometheus.io/scrape" = "true"
    "prometheus.io/port"   = tostring(local.hub_metrics_port)
    "prometheus.io/path"   = "/metrics"
  } : {}

  provider_context = {
    database = {
      host = local.database_host
      port = 5432
      name = local.database_name
      credentials_secret = {
        name         = local.database_credentials_secret_name
        username_key = "username"
        password_key = "password"
      }
    }
    prometheus = {
      query_endpoint = local.prometheus_query_endpoint
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
        bucket = local.warehouse_bucket_name
        region = local.region
      }
      spark_event_log_dir = local.spark_event_log_dir
      service_account = {
        annotations = local.workload_annotations.spark
      }
      flink_defaults = {
        serviceAccountAnnotations = local.workload_annotations.flink
      }
    }
    service_account_annotations = local.workload_annotations.orchestration
    secrets = {
      secret_store = {
        create = true
        name   = "zipline-secret-store"
        kind   = "SecretStore"
        spec = {
          provider = {
            gcpsm = {
              projectID = local.project_id
              auth = {
                workloadIdentity = {
                  clusterLocation = local.region
                  clusterName     = local.cluster_name
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
          key      = local.database_credentials_secret_name
          property = "username"
        }
        password = {
          key      = local.database_credentials_secret_name
          property = "password"
        }
      }
      auth_remote_refs = {
        for key in local.auth_secret_keys : key => {
          key = try(local.configured_auth_secret_ids[key], "")
        }
      }
    }
    runtime_env = [
      { name = "GOOGLE_CLOUD_PROJECT", value = local.project_id },
      { name = "GCP_PROJECT_ID", value = local.project_id },
      { name = "GCP_REGION", value = local.region },
      { name = "GKE_CLUSTER_NAME", value = local.cluster_name },
    ]
    values = {
      prometheus = {
        gcpPodMonitoring = {
          enabled  = true
          interval = "30s"
        }
      }
      starrocks = {
        feConfig = {
          run_mode                                   = "shared_data"
          cloud_native_storage_type                  = "GS"
          gcp_gcs_path                               = "${local.warehouse_bucket_name}/dataexplorer"
          gcp_gcs_use_compute_engine_service_account = true
          enable_load_volume_from_conf               = true
        }
        serviceAccount = local.orchestration_service_account
      }
      polaris = {
        extraEnv = [
          { name = "GOOGLE_CLOUD_PROJECT", value = local.project_id },
        ]
        bootstrap = {
          rbac = {
            catalog = {
              defaultBaseLocation = local.polaris_base_location
              storage = {
                type             = "GCS"
                allowedLocations = [local.polaris_base_location]
              }
            }
          }
        }
      }
      "ingress-nginx-ui" = {
        controller = {
          service = {
            type = "LoadBalancer"
          }
        }
      }
    }
  }
}
