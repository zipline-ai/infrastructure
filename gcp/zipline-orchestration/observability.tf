# Each CR below is keyed on the cluster's endpoint as well as its name: a cluster rebuilt under
# the same name takes the CRs with it, and a name-only trigger would not change, so nothing would
# reapply them. The endpoint is a new address for a new cluster.
#
# GMP PodMonitoring / ClusterPodMonitoring CRs. The chart exposes hub, fetcher,
# kube-state-metrics and operator metrics through pod annotations (hub_prometheus_pod_annotations
# in locals.tf and the chart's own prometheus.io defaults). GMP does not read Prometheus-style
# scrape annotations — it uses these CRs, so even in parity with AWS, metrics discovery is
# wire-level different.
#
# These are applied via terraform_data + kubectl rather than kubernetes_manifest
# because kubernetes_manifest builds its REST client at plan time, which creates
# a chicken-and-egg: `tofu plan` on an empty state (no cluster yet) fails on
# "no client config". The depends_on preserves ordering so this runs after the
# chart is up and the GMP CRDs have been registered by GKE.

locals {
  podmonitoring_hub_yaml = yamlencode({
    apiVersion = "monitoring.googleapis.com/v1"
    kind       = "PodMonitoring"
    metadata = {
      name      = "zipline-hub"
      namespace = local.orchestration_namespace
    }
    spec = {
      # The chart labels the Hub pod `app: orchestration-hub`, not `app: hub` — this selected
      # nothing for the life of the file, and `up{job="zipline-hub"}` had no target on
      # crucible-gke. The fetcher's selector happens to match its pod, which is why only it
      # reported and the gap went unnoticed.
      selector = { matchLabels = { app = "orchestration-hub" } }
      endpoints = [{
        # The port name, for the same reason as kube-state-metrics below: tostring of a number
        # renders a quoted string into an IntOrString, which is read as a port *named* "8905".
        # The Hub container names this port `metrics`. Fixing the selector alone left it with
        # still no target; both had to change.
        port     = "metrics"
        interval = "30s"
        path     = "/metrics"
      }]
    }
  })

  # kube-state-metrics ships with the chart and is enabled on every cloud, but its only
  # discovery mechanism there is the prometheus.io/scrape pod annotations, which AWS's AMP
  # pod_exporter job reads and GMP ignores. Without this CR the kube_* series exist nowhere
  # on GCP, and /monitor/crucible — which queries kube_node_info, kube_pod_info,
  # kube_pod_status_phase, kube_pod_status_ready and kube_resourcequota — renders empty.
  #
  # ClusterPodMonitoring, not PodMonitoring: KSM is a cluster-wide exporter, and its
  # namespace is not something this file should depend on.
  #
  # targetLabels narrows the pod-metadata labels GMP puts on the target to `namespace`
  # alone. GMP's default set also adds `pod` and `container`, which collide with KSM's own
  # labels of those names: KSM's `pod` is renamed to `exported_pod` and every series
  # collapses onto the KSM pod, so the dashboard's `on(pod, exported_namespace)` joins fail
  # with "found duplicate series". Observed on crucible-gke.
  #
  # The `namespace` target label is also what makes the dashboards match at all: KSM labels
  # each series with the namespace of the *object* it describes, as `namespace`, and
  # Prometheus renames a colliding scraped label to `exported_namespace`
  # (honor_labels=false). Every /monitor/crucible query filters
  # `exported_namespace=~"zipline-.*"`, so without the target label the series exist and
  # match nothing.
  clusterpodmonitoring_kube_state_metrics_yaml = yamlencode({
    apiVersion = "monitoring.googleapis.com/v1"
    kind       = "ClusterPodMonitoring"
    metadata   = { name = "zipline-kube-state-metrics" }
    spec = {
      selector = { matchLabels = { "app.kubernetes.io/name" = "kube-state-metrics" } }
      endpoints = [{
        # The port *name*, not the number. yamlencode renders `"8080"` as a quoted string, and the
        # CR's port field is an IntOrString — so a quoted number is read as a port named "8080",
        # nothing matches, and kube-state-metrics is never scraped. Observed on crucible-gke: the
        # CR sat applied for over two hours with no target in GMP while the two operator CRs
        # beside it, which use port names, had theirs. kube-state-metrics exposes `http` (8080,
        # the kube_* families) and `metrics` (8081, its own self-metrics); `http` is the one the
        # dashboards need, and naming it also makes the choice between the two explicit.
        port     = "http"
        interval = "30s"
        path     = "/metrics"
      }]
      targetLabels = { metadata = ["namespace"] }
    }
  })

  # Operator metrics. The chart's operators expose /metrics but, like KSM, were only ever
  # discovered through the AWS annotations. The dashboard's controller_runtime_reconcile_*,
  # workqueue_* and reconcile-error charts read them. Selected by component where an operator
  # ships more than one pod (spark's webhook shares app.kubernetes.io/name with its
  # controller). The flink-kubernetes-operator is absent on purpose: it declares no metrics
  # port and nothing listens on the default :9249, so its reporter has to be enabled in the
  # chart first.
  clusterpodmonitoring_spark_operator_yaml = yamlencode({
    apiVersion = "monitoring.googleapis.com/v1"
    kind       = "ClusterPodMonitoring"
    metadata   = { name = "zipline-spark-operator" }
    spec = {
      selector = {
        matchLabels = {
          "app.kubernetes.io/name"      = "spark-operator"
          "app.kubernetes.io/component" = "controller"
        }
      }
      endpoints = [{ port = "metrics", interval = "30s", path = "/metrics" }]
    }
  })

  clusterpodmonitoring_kuberay_operator_yaml = yamlencode({
    apiVersion = "monitoring.googleapis.com/v1"
    kind       = "ClusterPodMonitoring"
    metadata   = { name = "zipline-kuberay-operator" }
    spec = {
      selector  = { matchLabels = { "app.kubernetes.io/name" = "kuberay-operator" } }
      endpoints = [{ port = "http", interval = "30s", path = "/metrics" }]
    }
  })


  # Node-pool autoscaler limits. The chart's nodepool-exporter (GKE-only, reads
  # kube-system/cluster-autoscaler-status) exposes min/max/current nodes per pool; this scrapes it
  # so the Node Pools section can plot capacity against the autoscaler's limit. Selected by
  # component label so the selector does not depend on the release name.
  podmonitoring_nodepool_exporter_yaml = yamlencode({
    apiVersion = "monitoring.googleapis.com/v1"
    kind       = "PodMonitoring"
    metadata = {
      name      = "zipline-nodepool-exporter"
      namespace = local.orchestration_namespace
    }
    spec = {
      selector  = { matchLabels = { "app.kubernetes.io/component" = "nodepool-exporter" } }
      endpoints = [{ port = "metrics", interval = "30s", path = "/metrics" }]
    }
  })

  operator_clusterpodmonitorings = {
    zipline-spark-operator   = local.clusterpodmonitoring_spark_operator_yaml
    zipline-kuberay-operator = local.clusterpodmonitoring_kuberay_operator_yaml
  }

  podmonitoring_fetcher_yaml = yamlencode({
    apiVersion = "monitoring.googleapis.com/v1"
    kind       = "PodMonitoring"
    metadata = {
      name      = "zipline-fetcher"
      namespace = local.orchestration_namespace
    }
    spec = {
      selector = { matchLabels = { app = "fetcher" } }
      # Fetcher exposes Chronon and Vert.x metrics on separate ports.
      endpoints = [
        { port = "chronon-metrics", interval = "30s", path = "/metrics" },
        { port = "vertx-metrics", interval = "30s", path = "/metrics" },
      ]
    }
  })
}

resource "terraform_data" "podmonitoring_hub" {
  triggers_replace = {
    cluster   = google_container_cluster.main.name
    endpoint  = google_container_cluster.main.endpoint
    region    = local.cloud_args.region
    project   = local.cloud_args.project_id
    namespace = local.orchestration_namespace
    name      = "zipline-hub"
    yaml      = local.podmonitoring_hub_yaml
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      KUBE="$(mktemp)"; trap 'rm -f "$KUBE"' EXIT
      KUBECONFIG="$KUBE" gcloud container clusters get-credentials '${self.triggers_replace.cluster}' --region '${self.triggers_replace.region}' --project '${self.triggers_replace.project}' >/dev/null
      KUBECONFIG="$KUBE" kubectl apply -f - <<'YAML'
${self.triggers_replace.yaml}
YAML
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set +e
      KUBE="$(mktemp)"; trap 'rm -f "$KUBE"' EXIT
      KUBECONFIG="$KUBE" gcloud container clusters get-credentials '${self.triggers_replace.cluster}' --region '${self.triggers_replace.region}' --project '${self.triggers_replace.project}' >/dev/null 2>&1 || exit 0
      KUBECONFIG="$KUBE" kubectl delete podmonitoring.monitoring.googleapis.com '${self.triggers_replace.name}' -n '${self.triggers_replace.namespace}' --ignore-not-found 2>/dev/null || true
      exit 0
    EOT
  }

  depends_on = [module.zipline_orchestration]
}

resource "terraform_data" "podmonitoring_nodepool_exporter" {
  triggers_replace = {
    cluster   = google_container_cluster.main.name
    endpoint  = google_container_cluster.main.endpoint
    region    = local.cloud_args.region
    project   = local.cloud_args.project_id
    namespace = local.orchestration_namespace
    name      = "zipline-nodepool-exporter"
    yaml      = local.podmonitoring_nodepool_exporter_yaml
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      KUBE="$(mktemp)"; trap 'rm -f "$KUBE"' EXIT
      KUBECONFIG="$KUBE" gcloud container clusters get-credentials '${self.triggers_replace.cluster}' --region '${self.triggers_replace.region}' --project '${self.triggers_replace.project}' >/dev/null
      KUBECONFIG="$KUBE" kubectl apply -f - <<'YAML'
${self.triggers_replace.yaml}
YAML
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set +e
      KUBE="$(mktemp)"; trap 'rm -f "$KUBE"' EXIT
      KUBECONFIG="$KUBE" gcloud container clusters get-credentials '${self.triggers_replace.cluster}' --region '${self.triggers_replace.region}' --project '${self.triggers_replace.project}' >/dev/null 2>&1 || exit 0
      KUBECONFIG="$KUBE" kubectl delete podmonitoring.monitoring.googleapis.com '${self.triggers_replace.name}' -n '${self.triggers_replace.namespace}' --ignore-not-found 2>/dev/null || true
      exit 0
    EOT
  }

  depends_on = [module.zipline_orchestration]
}

resource "terraform_data" "clusterpodmonitoring_kube_state_metrics" {
  triggers_replace = {
    cluster  = google_container_cluster.main.name
    endpoint = google_container_cluster.main.endpoint
    region   = local.cloud_args.region
    project  = local.cloud_args.project_id
    name     = "zipline-kube-state-metrics"
    yaml     = local.clusterpodmonitoring_kube_state_metrics_yaml
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      KUBE="$(mktemp)"; trap 'rm -f "$KUBE"' EXIT
      KUBECONFIG="$KUBE" gcloud container clusters get-credentials '${self.triggers_replace.cluster}' --region '${self.triggers_replace.region}' --project '${self.triggers_replace.project}' >/dev/null
      KUBECONFIG="$KUBE" kubectl apply -f - <<'YAML'
${self.triggers_replace.yaml}
YAML
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set +e
      KUBE="$(mktemp)"; trap 'rm -f "$KUBE"' EXIT
      KUBECONFIG="$KUBE" gcloud container clusters get-credentials '${self.triggers_replace.cluster}' --region '${self.triggers_replace.region}' --project '${self.triggers_replace.project}' >/dev/null 2>&1 || exit 0
      KUBECONFIG="$KUBE" kubectl delete clusterpodmonitoring.monitoring.googleapis.com '${self.triggers_replace.name}' --ignore-not-found 2>/dev/null || true
      exit 0
    EOT
  }

  depends_on = [module.zipline_orchestration]
}

# The operator CRs are homogeneous, so they share one resource instead of one block each.
resource "terraform_data" "clusterpodmonitoring_operators" {
  for_each = local.operator_clusterpodmonitorings

  triggers_replace = {
    cluster  = google_container_cluster.main.name
    endpoint = google_container_cluster.main.endpoint
    region   = local.cloud_args.region
    project  = local.cloud_args.project_id
    name     = each.key
    yaml     = each.value
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      KUBE="$(mktemp)"; trap 'rm -f "$KUBE"' EXIT
      KUBECONFIG="$KUBE" gcloud container clusters get-credentials '${self.triggers_replace.cluster}' --region '${self.triggers_replace.region}' --project '${self.triggers_replace.project}' >/dev/null
      KUBECONFIG="$KUBE" kubectl apply -f - <<'YAML'
${self.triggers_replace.yaml}
YAML
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set +e
      KUBE="$(mktemp)"; trap 'rm -f "$KUBE"' EXIT
      KUBECONFIG="$KUBE" gcloud container clusters get-credentials '${self.triggers_replace.cluster}' --region '${self.triggers_replace.region}' --project '${self.triggers_replace.project}' >/dev/null 2>&1 || exit 0
      KUBECONFIG="$KUBE" kubectl delete clusterpodmonitoring.monitoring.googleapis.com '${self.triggers_replace.name}' --ignore-not-found 2>/dev/null || true
      exit 0
    EOT
  }

  depends_on = [module.zipline_orchestration]
}

resource "terraform_data" "podmonitoring_fetcher" {
  count = local.deploy_fetcher ? 1 : 0

  triggers_replace = {
    cluster   = google_container_cluster.main.name
    endpoint  = google_container_cluster.main.endpoint
    region    = local.cloud_args.region
    project   = local.cloud_args.project_id
    namespace = local.orchestration_namespace
    name      = "zipline-fetcher"
    yaml      = local.podmonitoring_fetcher_yaml
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      KUBE="$(mktemp)"; trap 'rm -f "$KUBE"' EXIT
      KUBECONFIG="$KUBE" gcloud container clusters get-credentials '${self.triggers_replace.cluster}' --region '${self.triggers_replace.region}' --project '${self.triggers_replace.project}' >/dev/null
      KUBECONFIG="$KUBE" kubectl apply -f - <<'YAML'
${self.triggers_replace.yaml}
YAML
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set +e
      KUBE="$(mktemp)"; trap 'rm -f "$KUBE"' EXIT
      KUBECONFIG="$KUBE" gcloud container clusters get-credentials '${self.triggers_replace.cluster}' --region '${self.triggers_replace.region}' --project '${self.triggers_replace.project}' >/dev/null 2>&1 || exit 0
      KUBECONFIG="$KUBE" kubectl delete podmonitoring.monitoring.googleapis.com '${self.triggers_replace.name}' -n '${self.triggers_replace.namespace}' --ignore-not-found 2>/dev/null || true
      exit 0
    EOT
  }

  depends_on = [module.zipline_orchestration]
}
