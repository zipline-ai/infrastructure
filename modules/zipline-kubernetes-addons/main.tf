locals {
  external_secrets_operator_values = merge({
    installCRDs = true
  }, var.external_secrets_operator_values)

  cert_manager_values = merge({
    installCRDs = true
  }, var.cert_manager_values)

  flink_operator_values = merge({
    webhook = {
      create = false
    }
  }, var.flink_operator_values)
}

resource "helm_release" "external_secrets_operator" {
  count = var.install_external_secrets_operator ? 1 : 0

  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  version          = var.external_secrets_operator_version

  values = [yamlencode(local.external_secrets_operator_values)]
}

resource "helm_release" "cert_manager" {
  count = var.install_cert_manager ? 1 : 0

  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  version          = var.cert_manager_version
  create_namespace = true

  values = [yamlencode(local.cert_manager_values)]
}

resource "helm_release" "opentelemetry_operator" {
  count = var.install_opentelemetry_operator ? 1 : 0

  name             = "opentelemetry-operator"
  repository       = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart            = "opentelemetry-operator"
  namespace        = "opentelemetry-operator-system"
  version          = var.opentelemetry_operator_version
  create_namespace = true

  values = [yamlencode(var.opentelemetry_operator_values)]

  depends_on = [helm_release.cert_manager]
}

resource "helm_release" "flink_operator" {
  count = var.install_flink_operator ? 1 : 0

  name             = "flink-kubernetes-operator"
  repository       = "https://archive.apache.org/dist/flink/flink-kubernetes-operator-${var.flink_operator_version}/"
  chart            = "flink-kubernetes-operator"
  namespace        = "flink-operator"
  version          = var.flink_operator_version
  create_namespace = true

  values = [yamlencode(local.flink_operator_values)]
}
