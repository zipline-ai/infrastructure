locals {
  secrets_store_csi_driver_values = merge({
    syncSecret = {
      enabled = true
    }
    enableSecretRotation = true
  }, var.secrets_store_csi_driver_values)

  cert_manager_values = merge({
    installCRDs = true
  }, var.cert_manager_values)

  flink_operator_values = merge({
    webhook = {
      create = false
    }
  }, var.flink_operator_values)
}

resource "helm_release" "secrets_store_csi_driver" {
  count = var.install_secrets_store_csi_driver ? 1 : 0

  name       = "secrets-store-csi-driver"
  repository = "https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts"
  chart      = "secrets-store-csi-driver"
  namespace  = "kube-system"
  version    = var.secrets_store_csi_driver_version

  values = [yamlencode(local.secrets_store_csi_driver_values)]
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
