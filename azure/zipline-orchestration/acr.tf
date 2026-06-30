data "azurerm_container_registry" "image_pull" {
  count = local.cloud_args.container_registry_name == "" ? 0 : 1

  name                = local.cloud_args.container_registry_name
  resource_group_name = local.cloud_args.container_registry_resource_group != "" ? local.cloud_args.container_registry_resource_group : local.resource_group_name
}

resource "azurerm_role_assignment" "aks_acr_pull" {
  count = local.cloud_args.container_registry_name == "" ? 0 : 1

  scope                = data.azurerm_container_registry.image_pull[0].id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}

