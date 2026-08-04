resource "azurerm_monitor_workspace" "prometheus" {
  name                          = local.monitor_workspace_name
  location                      = azurerm_resource_group.main.location
  resource_group_name           = azurerm_resource_group.main.name
  public_network_access_enabled = local.cloud_args.monitor_workspace_public_network_access
}

resource "azurerm_monitor_data_collection_rule_association" "prometheus_endpoint" {
  target_resource_id          = azurerm_kubernetes_cluster.main.id
  data_collection_endpoint_id = azurerm_monitor_workspace.prometheus.default_data_collection_endpoint_id
  description                 = "Azure Monitor managed Prometheus endpoint for Zipline metrics."
}

resource "azurerm_monitor_data_collection_rule_association" "prometheus_rule" {
  name                    = "zipline-prometheus-dcra"
  target_resource_id      = azurerm_kubernetes_cluster.main.id
  data_collection_rule_id = azurerm_monitor_workspace.prometheus.default_data_collection_rule_id
  description             = "Routes AKS Prometheus metrics to the Zipline Azure Monitor workspace."
}

resource "azurerm_role_assignment" "workload_monitoring_reader" {
  scope                = azurerm_monitor_workspace.prometheus.id
  role_definition_name = "Monitoring Reader"
  principal_id         = azurerm_user_assigned_identity.workload.principal_id
}

resource "kubernetes_config_map_v1" "ama_metrics_settings" {
  metadata {
    name      = "ama-metrics-settings-configmap"
    namespace = "kube-system"
  }

  data = {
    "schema-version"  = "v2"
    "config-version"  = "ver1"
    "cluster-metrics" = <<-EOT
      pod-annotation-based-scraping: |-
        podannotationnamespaceregex = "${local.orchestration_namespace}"
    EOT
  }
}
