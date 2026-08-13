resource "azurerm_monitor_workspace" "prometheus" {
  name                          = local.monitor_workspace_name
  location                      = azurerm_resource_group.main.location
  resource_group_name           = azurerm_resource_group.main.name
  public_network_access_enabled = local.cloud_args.monitor_workspace_public_network_access
}

resource "azurerm_monitor_data_collection_endpoint" "prometheus" {
  name                          = "MSPROM-${local.cloud_args.location}-${local.cluster_name}"
  location                      = azurerm_resource_group.main.location
  resource_group_name           = azurerm_resource_group.main.name
  kind                          = "Linux"
  public_network_access_enabled = local.cloud_args.monitor_workspace_public_network_access
  description                   = "Azure Monitor managed Prometheus endpoint for ${local.cluster_name}."
}

resource "azurerm_monitor_data_collection_rule" "prometheus" {
  name                        = "MSPROM-${local.cloud_args.location}-${local.cluster_name}"
  location                    = azurerm_resource_group.main.location
  resource_group_name         = azurerm_resource_group.main.name
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.prometheus.id
  description                 = "Azure Monitor managed Prometheus collection rule for ${local.cluster_name}."

  data_sources {
    prometheus_forwarder {
      name    = "PrometheusDataSource"
      streams = ["Microsoft-PrometheusMetrics"]
    }
  }

  destinations {
    monitor_account {
      monitor_account_id = azurerm_monitor_workspace.prometheus.id
      name               = "MonitoringAccount"
    }
  }

  data_flow {
    streams      = ["Microsoft-PrometheusMetrics"]
    destinations = ["MonitoringAccount"]
  }
}

resource "azurerm_monitor_data_collection_rule_association" "prometheus_endpoint" {
  target_resource_id          = azurerm_kubernetes_cluster.main.id
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.prometheus.id
  description                 = "Azure Monitor managed Prometheus endpoint for Zipline metrics."
}

resource "azurerm_monitor_data_collection_rule_association" "prometheus_rule" {
  name                    = "zipline-prometheus-dcra"
  target_resource_id      = azurerm_kubernetes_cluster.main.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.prometheus.id
  description             = "Routes AKS Prometheus metrics to the Zipline Azure Monitor workspace."
}

resource "azurerm_role_assignment" "aks_monitoring_metrics_publisher" {
  scope                = azurerm_monitor_data_collection_rule.prometheus.id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = azurerm_kubernetes_cluster.main.identity[0].principal_id
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

resource "kubernetes_config_map_v1" "ama_metrics_prometheus_config" {
  metadata {
    name      = "ama-metrics-prometheus-config"
    namespace = "kube-system"
  }

  data = {
    "prometheus-config" = <<-EOT
      global:
        scrape_interval: 30s
      scrape_configs:
        - job_name: zipline-pod-exporter
          kubernetes_sd_configs:
            - role: pod
          relabel_configs:
            - source_labels: [__meta_kubernetes_namespace]
              action: keep
              regex: ${local.orchestration_namespace}
            - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
              action: keep
              regex: "true"
            - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
              action: replace
              target_label: __metrics_path__
              regex: (.+)
            - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
              action: replace
              regex: ([^:]+)(?::[0-9]+)?;([0-9]+)
              replacement: $1:$2
              target_label: __address__
            - action: labelmap
              regex: __meta_kubernetes_pod_label_(.+)
            - source_labels: [__meta_kubernetes_namespace]
              action: replace
              target_label: kubernetes_namespace
            - source_labels: [__meta_kubernetes_namespace]
              action: replace
              target_label: namespace
            - source_labels: [__meta_kubernetes_pod_name]
              action: replace
              target_label: kubernetes_pod_name
    EOT
  }
}
