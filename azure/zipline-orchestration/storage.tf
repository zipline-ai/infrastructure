data "azurerm_storage_account" "shared" {
  name                = local.cloud_args.storage_account_name
  resource_group_name = local.storage_account_resource_group
}

resource "azurerm_storage_container" "this" {
  for_each = local.storage_container_names

  name                  = each.value
  storage_account_name  = data.azurerm_storage_account.shared.name
  container_access_type = "private"
}

resource "azurerm_storage_data_lake_gen2_path" "spark_events" {
  count = local.spark_event_log_managed ? 1 : 0

  path               = local.spark_event_log_path
  filesystem_name    = local.cloud_args.warehouse_container_name
  storage_account_id = data.azurerm_storage_account.shared.id
  resource           = "directory"

  depends_on = [
    azurerm_storage_container.this,
  ]
}

resource "azurerm_role_assignment" "workload_storage" {
  for_each = toset(local.cloud_args.storage_role_definition_names)

  scope                = data.azurerm_storage_account.shared.id
  role_definition_name = each.value
  principal_id         = azurerm_user_assigned_identity.workload.principal_id
}
