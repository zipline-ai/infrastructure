locals {
  orchestration_namespace       = try(var.orchestration.install.namespace, "zipline-system")
  orchestration_service_account = try(var.orchestration.service_account.name, "orchestration-sa")
  compute_namespaces            = try(var.orchestration.compute.namespaces, [{ name = "zipline-default" }])
  spark_service_account         = try(var.orchestration.compute.spark_service_account, "spark-operator-spark")
  flink_service_account         = try(var.orchestration.compute.flink_service_account, "flink")

  workload_identity_subjects = merge(
    {
      orchestration = "system:serviceaccount:${local.orchestration_namespace}:${local.orchestration_service_account}"
    },
    {
      for namespace in local.compute_namespaces :
      "spark-${namespace.name}" => "system:serviceaccount:${namespace.name}:${local.spark_service_account}"
    },
    {
      for namespace in local.compute_namespaces :
      "flink-${namespace.name}" => "system:serviceaccount:${namespace.name}:${local.flink_service_account}"
    },
  )
}

resource "azurerm_user_assigned_identity" "workload" {
  name                = local.workload_identity_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_federated_identity_credential" "workload" {
  for_each = local.workload_identity_subjects

  name                = substr(replace("${each.key}-federation", "_", "-"), 0, 120)
  resource_group_name = azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.workload.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.main.oidc_issuer_url
  subject             = each.value
}

resource "azurerm_role_assignment" "workload_resource_group" {
  for_each = toset(local.cloud_args.resource_group_role_definition_names)

  scope                = azurerm_resource_group.main.id
  role_definition_name = each.value
  principal_id         = azurerm_user_assigned_identity.workload.principal_id
}

