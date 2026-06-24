moved {
  from = kubernetes_namespace_v1.zipline_system
  to   = module.zipline_orchestration.kubernetes_namespace_v1.this[0]
}

moved {
  from = kubernetes_secret_v1.docker_hub_creds[0]
  to   = module.zipline_orchestration.kubernetes_secret_v1.docker_hub_creds[0]
}

moved {
  from = module.addons
  to   = module.zipline_orchestration.module.addons
}
