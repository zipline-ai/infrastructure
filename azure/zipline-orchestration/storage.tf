resource "azurerm_storage_container" "artifact" {
  name                  = local.artifact_container_name
  storage_account_name  = local.cloud_args.storage_account_name
  container_access_type = "private"
}

resource "azurerm_storage_container" "warehouse" {
  name                  = local.cloud_args.warehouse_container_name
  storage_account_name  = local.cloud_args.storage_account_name
  container_access_type = "private"
}

resource "azurerm_storage_container" "logs" {
  name                  = local.logs_container_name
  storage_account_name  = local.cloud_args.storage_account_name
  container_access_type = "private"
}
