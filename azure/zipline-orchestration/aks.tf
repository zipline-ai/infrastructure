locals {
  default_node_pool = merge({
    name                 = "nodepool1"
    vm_size              = "Standard_D4s_v3"
    node_count           = 3
    min_count            = 1
    max_count            = 10
    os_disk_size_gb      = 128
    os_disk_type         = "Managed"
    os_sku               = "Ubuntu"
    auto_scaling_enabled = true
  }, local.cloud_args.default_node_pool)
}

resource "azurerm_kubernetes_cluster" "main" {
  name                = local.cluster_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = local.aks_dns_prefix
  kubernetes_version  = local.cloud_args.kubernetes_version
  sku_tier            = "Free"

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  identity {
    type = "SystemAssigned"
  }

  monitor_metrics {
    annotations_allowed = local.cloud_args.monitor_metrics_annotations_allowed
    labels_allowed      = local.cloud_args.monitor_metrics_labels_allowed
  }

  default_node_pool {
    name                 = local.default_node_pool.name
    vm_size              = local.default_node_pool.vm_size
    vnet_subnet_id       = azurerm_subnet.aks.id
    enable_auto_scaling  = local.default_node_pool.auto_scaling_enabled
    node_count           = local.default_node_pool.node_count
    min_count            = local.default_node_pool.min_count
    max_count            = local.default_node_pool.max_count
    os_disk_size_gb      = local.default_node_pool.os_disk_size_gb
    os_disk_type         = local.default_node_pool.os_disk_type
    os_sku               = local.default_node_pool.os_sku
    orchestrator_version = local.cloud_args.kubernetes_version
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    service_cidr        = local.cloud_args.aks_service_cidr
    dns_service_ip      = local.cloud_args.aks_dns_service_ip
    pod_cidr            = local.cloud_args.aks_pod_cidr
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"
  }

  lifecycle {
    ignore_changes = [
      default_node_pool[0].node_count,
      default_node_pool[0].upgrade_settings,
    ]
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "user" {
  for_each = local.cloud_args.node_pools

  name                  = each.key
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = each.value.vm_size
  vnet_subnet_id        = azurerm_subnet.aks.id
  mode                  = try(each.value.mode, "User")
  enable_auto_scaling   = try(each.value.auto_scaling_enabled, true)
  node_count            = try(each.value.node_count, 0)
  min_count             = try(each.value.min_count, 0)
  max_count             = try(each.value.max_count, 3)
  os_sku                = try(each.value.os_sku, "Ubuntu")
  os_disk_type          = try(each.value.os_disk_type, "Managed")
  os_disk_size_gb       = try(each.value.os_disk_size_gb, 128)
  orchestrator_version  = local.cloud_args.kubernetes_version
  priority              = try(each.value.priority, "Regular")
  eviction_policy       = try(each.value.eviction_policy, null)
  spot_max_price        = try(each.value.spot_max_price, null)
  node_labels           = try(each.value.node_labels, {})
  node_taints           = try(each.value.node_taints, [])

  lifecycle {
    ignore_changes = [
      node_count,
      upgrade_settings,
    ]
  }
}
