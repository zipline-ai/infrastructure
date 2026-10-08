output "release_names" {
  description = "Helm release names installed by this module."
  value = compact([
    var.install_external_secrets_operator ? helm_release.external_secrets_operator[0].name : "",
    var.install_cert_manager ? helm_release.cert_manager[0].name : "",
    var.install_opentelemetry_operator ? helm_release.opentelemetry_operator[0].name : "",
    var.install_flink_operator ? helm_release.flink_operator[0].name : "",
    var.install_kuberay_operator ? helm_release.kuberay_operator[0].name : "",
    var.install_metrics_server ? helm_release.metrics_server[0].name : "",
  ])
}
