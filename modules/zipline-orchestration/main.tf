locals {
  chart_path = coalesce(var.chart_path, abspath("${path.module}/../../charts/zipline-orchestration"))
}

resource "kubernetes_namespace_v1" "this" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name        = var.namespace
    labels      = var.namespace_labels
    annotations = var.namespace_annotations
  }
}

resource "helm_release" "this" {
  name             = var.release_name
  chart            = local.chart_path
  namespace        = var.namespace
  create_namespace = false

  wait              = var.wait
  timeout           = var.timeout
  atomic            = var.atomic
  cleanup_on_fail   = var.cleanup_on_fail
  dependency_update = var.dependency_update

  values = concat(
    [yamlencode(var.values)],
    [for value in var.extra_values : yamlencode(value)],
    var.extra_values_yaml,
  )

  depends_on = [kubernetes_namespace_v1.this]
}
