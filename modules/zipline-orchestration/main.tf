locals {
  chart_path         = coalesce(var.chart_path, abspath("${path.module}/../../charts/zipline-orchestration"))
  chart_files        = sort(fileset(local.chart_path, "**"))
  chart_content_hash = sha256(join(",", [for file in local.chart_files : filesha256("${local.chart_path}/${file}")]))
  values_with_chart_hash = merge(var.values, {
    global = merge(try(var.values.global, {}), {
      chart_content_hash = local.chart_content_hash
    })
  })
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
    [yamlencode(local.values_with_chart_hash)],
    [for value in var.extra_values : yamlencode(value)],
    var.extra_values_yaml,
  )

  depends_on = [kubernetes_namespace_v1.this]
}
