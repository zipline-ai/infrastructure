# GMP PodMonitoring CRs. The chart emits hub + fetcher metrics via the pod
# annotations surfaced through hub_prometheus_pod_annotations (locals.tf). GMP
# does not read Prometheus-style scrape annotations — it uses PodMonitoring CRs,
# so even in parity with AWS, metrics discovery is wire-level different.
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
      selector = { matchLabels = { app = "hub" } }
      endpoints = [{
        port     = tostring(local.hub_metrics_port)
        interval = "30s"
        path     = "/metrics"
      }]
    }
  })

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

resource "terraform_data" "podmonitoring_fetcher" {
  count = local.deploy_fetcher ? 1 : 0

  triggers_replace = {
    cluster   = google_container_cluster.main.name
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
