locals {
  chart_path  = abspath(var.chart_path == "" ? "${path.module}/../../charts/zipline-orchestration" : var.chart_path)
  chart_files = sort(fileset(local.chart_path, "**"))

  install_defaults = {
    release_name          = "zipline-orchestration"
    namespace             = "zipline-system"
    create_namespace      = true
    namespace_labels      = {}
    namespace_annotations = {}
    helm_wait             = true
    helm_timeout          = 300
    atomic                = false
    cleanup_on_fail       = false
    dependency_update     = false
  }
  install = merge(local.install_defaults, try(var.orchestration.install, {}))

  image_pull_secret_defaults = {
    name               = "docker-hub-creds"
    create             = false
    dockerhub_username = "ziplineai"
    dockerhub_token    = ""
  }
  image_pull_secret      = merge(local.image_pull_secret_defaults, try(var.orchestration.image_pull_secret, {}))
  image_pull_secret_name = local.image_pull_secret.create ? kubernetes_secret_v1.docker_hub_creds[0].metadata[0].name : local.image_pull_secret.name
  image_pull_secrets     = local.image_pull_secret_name == "" ? [] : [{ name = local.image_pull_secret_name }]

  addons_defaults = {
    install_secrets_store_csi_driver = true
    install_cert_manager             = true
    install_flink_operator           = true
    install_opentelemetry_operator   = false
  }
  addons = merge(local.addons_defaults, try(var.orchestration.addons, {}))

  deployment = var.orchestration.deployment

  database_defaults = {
    jdbc_url = ""
    url      = ""
    port     = 5432
    name     = "execution_info"
    ssl_mode = "require"
  }
  database = merge(local.database_defaults, var.orchestration.database)

  database_credentials_secret_defaults = {
    name         = "db-credentials"
    username_key = "username"
    password_key = "password"
  }
  database_credentials_secret = merge(local.database_credentials_secret_defaults, try(local.database.credentials_secret, {}))

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

  secrets_defaults = {
    class_name = "zipline-secret-provider"
    database_object_names = {
      username = "username"
      password = "password"
    }
    auth_object_names    = { for key in local.auth_secret_keys : key => key }
    extra_secret_objects = []
  }
  secrets_input = try(var.orchestration.secrets, {})
  secrets = merge(local.secrets_defaults, local.secrets_input, {
    database_object_names = merge(local.secrets_defaults.database_object_names, try(local.secrets_input.database_object_names, {}))
    auth_object_names     = merge(local.secrets_defaults.auth_object_names, try(local.secrets_input.auth_object_names, {}))
  })
  auth_enabled = try(var.orchestration.auth.enabled, false)

  service_account_defaults = {
    create      = true
    name        = "orchestration-sa"
    annotations = {}
  }
  service_account_input = try(var.orchestration.service_account, {})
  service_account = merge(local.service_account_defaults, local.service_account_input, {
    annotations = merge(
      local.service_account_defaults.annotations,
      try(local.service_account_input.annotations, {}),
      try(var.orchestration.provider_service_account_annotations, {}),
    )
  })

  hub_defaults = {
    chronon_metrics_reader       = "http"
    table_partitions_dataset     = "TABLE_PARTITIONS"
    data_quality_metrics_dataset = "DATA_QUALITY_METRICS"
    image                        = ""
    verticle_class               = ""
    env                          = []
  }
  hub                = merge(local.hub_defaults, try(var.orchestration.hub, {}))
  hub_verticle_class = local.hub.verticle_class != "" ? local.hub.verticle_class : try(local.hub.verticleClass, "")

  eval_defaults = {
    image = ""
  }
  eval = merge(local.eval_defaults, try(var.orchestration.eval, {}))

  hub_env = concat(
    local.hub.chronon_metrics_reader == "" ? [] : [
      {
        name  = "CHRONON_METRICS_READER"
        value = local.hub.chronon_metrics_reader
      }
    ],
    local.hub.table_partitions_dataset == "" ? [] : [
      {
        name  = "TABLE_PARTITIONS_DATASET"
        value = local.hub.table_partitions_dataset
      }
    ],
    local.hub.data_quality_metrics_dataset == "" ? [] : [
      {
        name  = "DATA_QUALITY_METRICS_DATASET"
        value = local.hub.data_quality_metrics_dataset
      }
    ],
    try(var.orchestration.provider_hub_env, []),
    local.hub.env,
    try(var.orchestration.hub_env, []),
  )

  database_secret_object = {
    secretName = local.database_credentials_secret.name
    type       = "Opaque"
    data = [
      {
        objectName = local.secrets.database_object_names.password
        key        = local.database_credentials_secret.password_key
      },
      {
        objectName = local.secrets.database_object_names.username
        key        = local.database_credentials_secret.username_key
      },
    ]
  }

  auth_secret_object = {
    secretName = "auth-secret"
    type       = "Opaque"
    data = [
      for key in local.auth_secret_keys : {
        objectName = local.secrets.auth_object_names[key]
        key        = key
      }
    ]
  }

  secret_objects = concat(
    [local.database_secret_object],
    local.auth_enabled ? [local.auth_secret_object] : [],
    try(var.orchestration.extra_secret_objects, []),
    local.secrets.extra_secret_objects,
  )

  ingress_defaults = {
    class_name                  = "nginx-ui"
    tls_secret_name             = ""
    cert_manager_cluster_issuer = ""
    annotations                 = {}
  }
  ingress = merge(local.ingress_defaults, var.orchestration.ingress)

  cert_manager_annotations = local.ingress.cert_manager_cluster_issuer == "" ? {} : {
    "cert-manager.io/cluster-issuer" = local.ingress.cert_manager_cluster_issuer
  }

  app_tls = local.ingress.tls_secret_name != "" ? [{
    hosts      = [local.ingress.domain]
    secretName = local.ingress.tls_secret_name
  }] : []

  ingress_annotations = merge(
    local.cert_manager_annotations,
    local.ingress.annotations,
  )

  compute_defaults = {
    default_namespace      = "zipline-default"
    namespaces             = [{ name = "zipline-default", team = "default" }]
    spark_image            = "ziplineai/spark:nightly"
    flink_image            = "ziplineai/flink:1.20.3"
    spark_service_account  = "spark-operator-spark"
    flink_service_account  = "flink"
    spark_event_log_dir    = ""
    rbac_create            = true
    image_prepull_enabled  = true
    image_prepull_images   = []
    history_server_image   = ""
    history_server_options = []
    spark_defaults         = {}
    flink_defaults         = {}
    object_store = {
      bucket = ""
      region = ""
    }
    service_account         = {}
    image_prepull_overrides = {}
  }
  compute                           = merge(local.compute_defaults, try(var.orchestration.compute, {}))
  compute_object_store_bucket_input = try(local.compute.object_store.bucket, "")
  compute_object_store_bucket       = local.compute_object_store_bucket_input == null ? "" : tostring(local.compute_object_store_bucket_input)

  compute_service_account_defaults = {
    annotations = {}
  }
  compute_service_account = merge(local.compute_service_account_defaults, local.compute.service_account)

  compute_spark_defaults = merge(
    {
      eventLogDir = local.compute.spark_event_log_dir
      image       = local.compute.spark_image
    },
    local.compute.spark_defaults,
  )

  compute_flink_defaults = merge(
    {
      image          = local.compute.flink_image
      serviceAccount = local.compute.flink_service_account
    },
    local.compute.flink_defaults,
  )

  compute_image_prepull = merge(
    {
      enabled = local.compute.image_prepull_enabled
      images  = length(local.compute.image_prepull_images) > 0 ? local.compute.image_prepull_images : (local.compute.image_prepull_enabled ? [local.compute.spark_image] : [])
    },
    local.compute.image_prepull_overrides,
  )

  compute_history_server = {
    image                 = local.compute.history_server_image != "" ? local.compute.history_server_image : local.compute.spark_image
    extraSparkHistoryOpts = local.compute.history_server_options
  }

  prometheus_defaults = {
    query_endpoint = ""
  }
  prometheus = merge(local.prometheus_defaults, try(var.orchestration.prometheus, {}))

  chart_content_hash = sha256(join(",", [for file in local.chart_files : filesha256("${local.chart_path}/${file}")]))

  common_values = {
    global = {
      customer_name      = local.deployment.customer_name
      artifact_prefix    = local.deployment.artifact_prefix
      version            = local.deployment.zipline_version
      deploy_fetcher     = try(local.deployment.deploy_fetcher, false)
      chart_content_hash = local.chart_content_hash
    }

    runtime = {
      env = concat(
        try(var.orchestration.provider_runtime_env, []),
        try(var.orchestration.runtime_env, []),
      )
    }

    imagePullSecrets = local.image_pull_secrets

    serviceAccount = {
      create      = local.service_account.create
      name        = local.service_account.name
      annotations = local.service_account.annotations
    }

    database = {
      jdbcUrl = local.database.jdbc_url
      url     = local.database.url
      host    = local.database.host
      port    = local.database.port
      name    = local.database.name
      sslMode = local.database.ssl_mode
      credentialsSecret = {
        name        = local.database_credentials_secret.name
        usernameKey = local.database_credentials_secret.username_key
        passwordKey = local.database_credentials_secret.password_key
      }
    }

    secrets = {
      className     = local.secrets.class_name
      secretObjects = local.secret_objects
    }

    compute = {
      enabled          = true
      defaultNamespace = local.compute.default_namespace
      namespaces       = local.compute.namespaces
      objectStore      = local.compute.object_store
      serviceAccount = {
        sparkName   = local.compute.spark_service_account
        flinkName   = local.compute.flink_service_account
        annotations = local.compute_service_account.annotations
      }
      rbac = {
        create = local.compute.rbac_create
      }
      sparkDefaults = local.compute_spark_defaults
      flinkDefaults = local.compute_flink_defaults
      imagePrepull  = local.compute_image_prepull
      historyServer = local.compute_history_server
    }

    ingress = {
      ui = {
        className   = local.ingress.class_name
        host        = local.ingress.domain
        tls         = local.app_tls
        annotations = local.ingress_annotations
      }
      hub = {
        className   = local.ingress.class_name
        host        = local.ingress.domain
        tls         = local.app_tls
        annotations = local.ingress_annotations
      }
      fetcher = {
        className   = local.ingress.class_name
        host        = local.ingress.domain
        tls         = local.app_tls
        annotations = local.ingress_annotations
      }
      eval = {
        className   = local.ingress.class_name
        host        = local.ingress.domain
        tls         = local.app_tls
        annotations = local.ingress_annotations
      }
      polaris = {
        className = local.ingress.class_name
      }
    }

    prometheus = {
      queryEndpoint = local.prometheus.query_endpoint
      namespace     = local.install.namespace
    }

    auth = try(var.orchestration.auth, { enabled = false })

    orchestration = {
      hub = {
        image         = local.hub.image
        verticleClass = local.hub_verticle_class
        env           = local.hub_env
      }
      ui = {
        env = concat(
          try(var.orchestration.provider_ui_env, []),
          try(var.orchestration.ui_env, []),
        )
      }
      fetcher = {
        env = concat(
          try(var.orchestration.provider_fetcher_env, []),
          try(var.orchestration.fetcher_env, []),
        )
      }
      eval = {
        image = local.eval.image
        env = concat(
          try(var.orchestration.provider_eval_env, []),
          try(var.orchestration.eval_env, []),
        )
      }
    }
  }
}

resource "terraform_data" "configuration_validation" {
  input = {
    create_image_pull_secret = local.image_pull_secret.create
    object_store_bucket      = local.compute_object_store_bucket
  }

  lifecycle {
    precondition {
      condition     = !local.image_pull_secret.create || trimspace(local.image_pull_secret.dockerhub_token) != ""
      error_message = "orchestration.image_pull_secret.dockerhub_token must be set when orchestration.image_pull_secret.create is true."
    }

    precondition {
      condition     = !strcontains(local.compute_object_store_bucket, "://")
      error_message = "orchestration.compute.object_store.bucket must be a bucket/container name only, not a URI."
    }
  }
}

resource "kubernetes_namespace_v1" "this" {
  count = local.install.create_namespace ? 1 : 0

  metadata {
    name        = local.install.namespace
    labels      = local.install.namespace_labels
    annotations = local.install.namespace_annotations
  }
}

resource "kubernetes_secret_v1" "docker_hub_creds" {
  count = local.image_pull_secret.create ? 1 : 0

  metadata {
    name      = local.image_pull_secret.name
    namespace = local.install.namespace
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "https://index.docker.io/v1/" = {
          username = local.image_pull_secret.dockerhub_username
          password = local.image_pull_secret.dockerhub_token
          auth     = base64encode("${local.image_pull_secret.dockerhub_username}:${local.image_pull_secret.dockerhub_token}")
        }
      }
    })
  }

  depends_on = [kubernetes_namespace_v1.this]
}

module "addons" {
  source = "../zipline-kubernetes-addons"

  install_secrets_store_csi_driver = local.addons.install_secrets_store_csi_driver
  install_cert_manager             = local.addons.install_cert_manager
  install_flink_operator           = local.addons.install_flink_operator
  install_opentelemetry_operator   = local.addons.install_opentelemetry_operator
}

resource "helm_release" "this" {
  name             = local.install.release_name
  chart            = local.chart_path
  namespace        = local.install.namespace
  create_namespace = false

  wait              = local.install.helm_wait
  timeout           = local.install.helm_timeout
  atomic            = local.install.atomic
  cleanup_on_fail   = local.install.cleanup_on_fail
  dependency_update = local.install.dependency_update

  values = concat(
    [yamlencode(local.common_values)],
    [yamlencode(try(var.orchestration.values, {}))],
    [for value in try(var.orchestration.extra_values, []) : yamlencode(value)],
    try(var.orchestration.extra_values_yaml, []),
  )

  depends_on = [
    terraform_data.configuration_validation,
    kubernetes_namespace_v1.this,
    kubernetes_secret_v1.docker_hub_creds,
    module.addons,
  ]
}
