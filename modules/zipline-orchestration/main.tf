locals {
  chart_path  = abspath(var.chart_path == "" ? "${path.module}/../../charts/zipline-orchestration" : var.chart_path)
  chart_files = sort(fileset(local.chart_path, "**"))

  orchestration_input        = var.orchestration
  provider_context           = var.provider_context
  provider_compute           = try(local.provider_context.compute, {})
  provider_secrets           = try(local.provider_context.secrets, {})
  provider_database          = try(local.provider_context.database, {})
  provider_prometheus        = try(local.provider_context.prometheus, {})
  orchestration_compute      = try(local.orchestration_input.compute, {})
  orchestration_secrets      = try(local.orchestration_input.secrets, {})
  orchestration_database     = try(local.orchestration_input.database, {})
  orchestration_prometheus   = try(local.orchestration_input.prometheus, {})
  orchestration_image_secret = try(local.orchestration_input.image_pull_secret, {})
  orchestration_ingress      = try(local.orchestration_input.ingress, {})
  orchestration_addons       = try(local.orchestration_input.addons, {})

  orchestration = merge(local.orchestration_input, {
    hub = merge(
      try(local.orchestration_input.hub, {}),
      try(local.provider_context.hub, {}),
    )
    eval = merge(
      try(local.orchestration_input.eval, {}),
      try(local.provider_context.eval, {}),
    )
    database = merge(
      local.orchestration_database,
      local.provider_database,
    )
    prometheus = merge(
      local.orchestration_prometheus,
      local.provider_prometheus,
    )
    compute = merge(local.orchestration_compute, local.provider_compute, {
      service_account = merge(
        try(local.orchestration_compute.service_account, {}),
        try(local.provider_compute.service_account, {}),
      )
      spark_defaults = merge(
        try(local.orchestration_compute.spark_defaults, {}),
        try(local.provider_compute.spark_defaults, {}),
      )
      flink_defaults = merge(
        try(local.orchestration_compute.flink_defaults, {}),
        try(local.provider_compute.flink_defaults, {}),
      )
      history_server_options = concat(
        try(local.provider_compute.history_server_options, []),
        try(local.orchestration_compute.history_server_options, []),
      )
    })
    image_pull_secret = merge(
      try(local.provider_context.image_pull_secret, {}),
      local.orchestration_image_secret,
    )
    ingress = merge(
      try(local.provider_context.ingress, {}),
      local.orchestration_ingress,
    )
    addons = merge(
      local.orchestration_addons,
      try(local.provider_context.addons, {}),
    )
    secrets = merge(local.orchestration_secrets, local.provider_secrets, {
      secret_store = merge(
        try(local.provider_secrets.secret_store, {}),
        try(local.orchestration_secrets.secret_store, {}),
      )
      database_remote_refs = merge(
        try(local.provider_secrets.database_remote_refs, {}),
        try(local.orchestration_secrets.database_remote_refs, {}),
      )
      auth_remote_refs = merge(
        try(local.provider_secrets.auth_remote_refs, {}),
        try(local.orchestration_secrets.auth_remote_refs, {}),
      )
      extra_external_secrets = concat(
        try(local.orchestration_secrets.extra_external_secrets, []),
        try(local.provider_secrets.extra_external_secrets, []),
      )
    })
    provider_service_account_annotations = try(local.provider_context.service_account_annotations, try(local.orchestration_input.provider_service_account_annotations, {}))
    provider_runtime_env                 = try(local.provider_context.runtime_env, try(local.orchestration_input.provider_runtime_env, []))
    provider_hub_env                     = try(local.provider_context.hub_env, try(local.orchestration_input.provider_hub_env, []))
    provider_ui_env                      = try(local.provider_context.ui_env, try(local.orchestration_input.provider_ui_env, []))
    provider_fetcher_env                 = try(local.provider_context.fetcher_env, try(local.orchestration_input.provider_fetcher_env, []))
    provider_eval_env                    = try(local.provider_context.eval_env, try(local.orchestration_input.provider_eval_env, []))
    values                               = try(local.provider_context.values, try(local.orchestration_input.values, {}))
  })

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
  install = merge(local.install_defaults, try(local.orchestration.install, {}))

  image_pull_secret_defaults = {
    name               = "docker-hub-creds"
    create             = false
    dockerhub_username = "ziplineai"
    dockerhub_token    = ""
  }
  image_pull_secret      = merge(local.image_pull_secret_defaults, try(local.orchestration.image_pull_secret, {}))
  image_pull_secret_name = local.image_pull_secret.create ? kubernetes_secret_v1.docker_hub_creds[0].metadata[0].name : local.image_pull_secret.name
  image_pull_secrets     = local.image_pull_secret_name == "" ? [] : [{ name = local.image_pull_secret_name }]
  helm_release_name      = local.install.release_name
  helm_fullname          = strcontains(local.helm_release_name, "zipline-orchestration") ? local.helm_release_name : "${local.helm_release_name}-zipline-orchestration"
  loki_service_url       = "http://${local.helm_fullname}-loki.${local.install.namespace}.svc.cluster.local:3100/loki/api/v1/push"

  addons_defaults = {
    install_external_secrets_operator = true
    install_cert_manager              = true
    install_flink_operator            = true
    install_opentelemetry_operator    = false
    external_secrets_operator_values  = {}
    cert_manager_values               = {}
  }
  addons = merge(local.addons_defaults, try(local.orchestration.addons, {}))

  deployment = local.orchestration.deployment

  database_defaults = {
    jdbc_url = ""
    url      = ""
    port     = 5432
    name     = "execution_info"
    ssl_mode = "require"
  }
  database = merge(local.database_defaults, local.orchestration.database)

  database_credentials_secret_defaults = {
    name         = "db-credentials"
    username_key = "username"
    password_key = "password"
  }
  database_credentials_secret = merge(local.database_credentials_secret_defaults, try(local.database.credentials_secret, {}))

  auth_saml_enabled = try(local.orchestration.auth.sso_use_saml, false)
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
    external_secrets_enabled = true
    refresh_interval         = "1h"
    secret_store = {
      create = true
      name   = "zipline-secret-store"
      kind   = "SecretStore"
      spec   = {}
    }
    database_remote_refs = {
      username = {}
      password = {}
    }
    auth_remote_refs       = { for key in local.auth_secret_keys : key => {} }
    extra_external_secrets = []
  }
  secrets_input = try(local.orchestration.secrets, {})
  secrets = merge(local.secrets_defaults, local.secrets_input, {
    secret_store         = merge(local.secrets_defaults.secret_store, try(local.secrets_input.secret_store, {}))
    database_remote_refs = merge(local.secrets_defaults.database_remote_refs, try(local.secrets_input.database_remote_refs, {}))
    auth_remote_refs     = merge(local.secrets_defaults.auth_remote_refs, try(local.secrets_input.auth_remote_refs, {}))
  })
  auth_enabled = try(local.orchestration.auth.enabled, false)

  service_account_defaults = {
    create      = true
    name        = "orchestration-sa"
    annotations = {}
  }
  service_account_input = try(local.orchestration.service_account, {})
  service_account = merge(local.service_account_defaults, local.service_account_input, {
    annotations = merge(
      local.service_account_defaults.annotations,
      try(local.service_account_input.annotations, {}),
      try(local.orchestration.provider_service_account_annotations, {}),
    )
  })

  hub_input = try(local.orchestration.hub, {})
  hub_defaults = {
    chronon_metrics_reader       = "prometheus"
    data_quality_metrics_dataset = "DATA_QUALITY_METRICS"
    image                        = ""
    metrics_port                 = null
    pod_annotations              = {}
    verticle_class               = ""
    env                          = []
  }
  hub                = merge(local.hub_defaults, local.hub_input)
  hub_verticle_class = local.hub.verticle_class != "" ? local.hub.verticle_class : try(local.hub.verticleClass, "")
  hub_chronon_metrics_reader = (
    try(local.hub_input.chronon_metrics_reader, null) != null
    ? local.hub_input.chronon_metrics_reader
    : (
      try(local.hub_input.metricsReader, null) != null
      ? local.hub_input.metricsReader
      : local.hub_defaults.chronon_metrics_reader
    )
  )
  hub_explicit_metrics_port = (
    try(local.hub_input.metrics_port, null) != null
    ? local.hub_input.metrics_port
    : try(local.hub_input.metricsPort, null)
  )
  hub_metrics_port = (
    local.hub_chronon_metrics_reader == "prometheus"
    ? (
      local.hub_explicit_metrics_port != null
      ? local.hub_explicit_metrics_port
      : 8905
    )
    : local.hub_explicit_metrics_port
  )

  eval_defaults = {
    image = ""
  }
  eval = merge(local.eval_defaults, try(local.orchestration.eval, {}))

  ui_defaults = {
    origin = ""
  }
  ui = merge(local.ui_defaults, try(local.orchestration.ui, {}))

  hub_env = concat(
    local.hub.data_quality_metrics_dataset == "" ? [] : [
      {
        name  = "DATA_QUALITY_METRICS_DATASET"
        value = local.hub.data_quality_metrics_dataset
      }
    ],
    try(local.orchestration.provider_hub_env, []),
    local.hub.env,
    try(local.orchestration.hub_env, []),
  )

  database_external_secret = {
    name = local.database_credentials_secret.name
    spec = {
      refreshInterval = local.secrets.refresh_interval
      secretStoreRef = {
        name = local.secrets.secret_store.name
        kind = local.secrets.secret_store.kind
      }
      target = {
        name           = local.database_credentials_secret.name
        creationPolicy = "Owner"
        template = {
          type = "Opaque"
        }
      }
      data = [
        {
          secretKey = local.database_credentials_secret.password_key
          remoteRef = local.secrets.database_remote_refs.password
        },
        {
          secretKey = local.database_credentials_secret.username_key
          remoteRef = local.secrets.database_remote_refs.username
        },
      ]
    }
  }

  auth_external_secret = {
    name = "auth-secret"
    spec = {
      refreshInterval = local.secrets.refresh_interval
      secretStoreRef = {
        name = local.secrets.secret_store.name
        kind = local.secrets.secret_store.kind
      }
      target = {
        name           = "auth-secret"
        creationPolicy = "Owner"
        template = {
          type = "Opaque"
        }
      }
      data = [
        for key in local.auth_secret_keys : {
          secretKey = key
          remoteRef = local.secrets.auth_remote_refs[key]
        }
      ]
    }
  }

  external_secret_targets = concat(
    [local.database_external_secret],
    local.auth_enabled ? [local.auth_external_secret] : [],
    local.secrets.extra_external_secrets,
  )

  database_remote_refs_configured = alltrue([
    for ref in values(local.secrets.database_remote_refs) : trimspace(tostring(try(ref.key, ""))) != ""
  ])
  auth_remote_refs_configured = alltrue([
    for key in local.auth_secret_keys : trimspace(tostring(try(local.secrets.auth_remote_refs[key].key, ""))) != ""
  ])

  legacy_secret_objects = concat(
    try(local.orchestration.extra_secret_objects, []),
    try(local.secrets.extra_secret_objects, []),
  )

  legacy_object_names = concat(
    compact(values(try(local.secrets.database_object_names, {}))),
    compact(values(try(local.secrets.auth_object_names, {}))),
  )

  legacy_secret_provider_class_name = try(local.secrets.class_name, "")

  ingress_defaults = {
    class_name                   = "nginx-ui"
    tls_secret_name              = ""
    cert_manager_cluster_issuer  = ""
    create_cluster_issuer        = false
    cluster_issuer_email         = ""
    cluster_issuer_server        = "https://acme-v02.api.letsencrypt.org/directory"
    cluster_issuer_secret_name   = ""
    cluster_issuer_ingress_class = ""
    annotations                  = {}
  }
  ingress = merge(local.ingress_defaults, local.orchestration.ingress)

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
    namespace_defaults     = {}
    object_store = {
      bucket = ""
      region = ""
    }
    service_account         = {}
    image_prepull_overrides = {}
  }
  compute                           = merge(local.compute_defaults, try(local.orchestration.compute, {}))
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
      image                     = local.compute.flink_image
      serviceAccount            = local.compute.flink_service_account
      serviceAccountAnnotations = local.compute_service_account.annotations
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
  # Crucible warm pool (driver-sized pause pods) + Spark priority classes.
  # Disabled by default; enable + target a driver pool via compute.warm_pool.
  # do-not-disrupt keeps Karpenter from consolidating the pre-warmed nodes away.
  compute_warm_pool = merge(
    {
      enabled           = false
      replicas          = 2
      priorityClassName = "zipline-spark-pause"
      annotations       = { "karpenter.sh/do-not-disrupt" = "true" }
      resources         = { cpu = "2", memory = "4Gi" }
    },
    try(local.compute.warm_pool, {}),
  )
  compute_driver_priority_class = merge(
    { enabled = false, name = "zipline-spark-driver", value = 100 },
    try(local.compute.driver_priority_class, {}),
  )
  compute_system_priority_class = merge(
    { enabled = false, name = "zipline-compute-system", value = 1000 },
    try(local.compute.system_priority_class, {}),
  )

  compute_history_server = {
    image                 = local.compute.history_server_image != "" ? local.compute.history_server_image : local.compute.spark_image
    extraSparkHistoryOpts = local.compute.history_server_options
  }

  prometheus_defaults = {
    query_endpoint = ""
  }
  prometheus = merge(local.prometheus_defaults, try(local.orchestration.prometheus, {}))

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
        try(local.orchestration.provider_runtime_env, []),
        try(local.orchestration.runtime_env, []),
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
      externalSecrets = {
        enabled         = local.secrets.external_secrets_enabled
        refreshInterval = local.secrets.refresh_interval
        secretStore     = local.secrets.secret_store
        targets         = local.external_secret_targets
      }
    }

    compute = {
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
      sparkDefaults       = local.compute_spark_defaults
      flinkDefaults       = local.compute_flink_defaults
      namespaceDefaults   = local.compute.namespace_defaults
      imagePrepull        = local.compute_image_prepull
      historyServer       = local.compute_history_server
      warmPool            = local.compute_warm_pool
      driverPriorityClass = local.compute_driver_priority_class
      systemPriorityClass = local.compute_system_priority_class
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
        tls       = local.app_tls
      }
    }

    prometheus = {
      queryEndpoint = local.prometheus.query_endpoint
      namespace     = local.install.namespace
    }

    promtail = {
      config = {
        clients = [
          {
            url = local.loki_service_url
          }
        ]
      }
    }

    certManager = {
      enabled     = local.addons.install_cert_manager
      installCRDs = local.addons.install_cert_manager
    }

    clusterIssuer = {
      enabled              = local.ingress.create_cluster_issuer
      name                 = local.ingress.cert_manager_cluster_issuer != "" ? local.ingress.cert_manager_cluster_issuer : "letsencrypt-prod"
      email                = local.ingress.cluster_issuer_email
      server               = local.ingress.cluster_issuer_server
      privateKeySecretName = local.ingress.cluster_issuer_secret_name
      ingressClass         = local.ingress.cluster_issuer_ingress_class != "" ? local.ingress.cluster_issuer_ingress_class : local.ingress.class_name
    }

    auth = {
      for key, value in try(local.orchestration.auth, { enabled = false }) : key => value
      if key != "jwksUrl"
    }

    orchestration = {
      hub = {
        image          = local.hub.image
        verticleClass  = local.hub_verticle_class
        metricsReader  = local.hub_chronon_metrics_reader
        metricsPort    = local.hub_metrics_port
        podAnnotations = try(local.hub.pod_annotations, try(local.hub.podAnnotations, {}))
        env            = local.hub_env
      }
      ui = {
        origin = local.ui.origin
        env = concat(
          try(local.orchestration.provider_ui_env, []),
          try(local.orchestration.ui_env, []),
        )
      }
      fetcher = {
        env = concat(
          try(local.orchestration.provider_fetcher_env, []),
          try(local.orchestration.fetcher_env, []),
        )
      }
      eval = {
        image = local.eval.image
        env = concat(
          try(local.orchestration.provider_eval_env, []),
          try(local.orchestration.eval_env, []),
        )
      }
    }
  }
}

resource "terraform_data" "configuration_validation" {
  input = {
    create_image_pull_secret = local.image_pull_secret.create
    object_store_bucket      = local.compute_object_store_bucket
    secrets_enabled          = local.secrets.external_secrets_enabled
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

    precondition {
      condition     = !local.secrets.external_secrets_enabled || local.database_remote_refs_configured
      error_message = "orchestration.secrets.database_remote_refs.username.key and password.key must be set when External Secrets are enabled."
    }

    precondition {
      condition     = !local.secrets.external_secrets_enabled || !local.auth_enabled || local.auth_remote_refs_configured
      error_message = "orchestration.secrets.auth_remote_refs must include a remoteRef.key for every enabled auth secret key."
    }

    precondition {
      condition     = length(local.legacy_secret_objects) == 0 && length(local.legacy_object_names) == 0 && local.legacy_secret_provider_class_name == ""
      error_message = "SecretProviderClass values are no longer supported. Use orchestration.secrets.database_remote_refs, auth_remote_refs, and extra_external_secrets for External Secrets Operator."
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

  install_external_secrets_operator = local.addons.install_external_secrets_operator
  external_secrets_operator_values  = local.addons.external_secrets_operator_values
  install_cert_manager              = local.addons.install_cert_manager
  cert_manager_values               = local.addons.cert_manager_values
  install_flink_operator            = local.addons.install_flink_operator
  install_opentelemetry_operator    = local.addons.install_opentelemetry_operator
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
    [yamlencode(try(local.orchestration.values, {}))],
    [for value in try(local.orchestration.extra_values, []) : yamlencode(value)],
    try(local.orchestration.extra_values_yaml, []),
  )

  depends_on = [
    terraform_data.configuration_validation,
    kubernetes_namespace_v1.this,
    kubernetes_secret_v1.docker_hub_creds,
    module.addons,
  ]
}

data "kubernetes_service_v1" "ingress_controller" {
  metadata {
    name      = "${local.install.release_name}-ingress-nginx-ui-controller"
    namespace = local.install.namespace
  }

  depends_on = [helm_release.this]
}
