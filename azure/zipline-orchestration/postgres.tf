resource "azurerm_private_dns_zone" "postgres" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "${local.cluster_name}-postgres"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = azurerm_virtual_network.main.id
}

resource "azurerm_postgresql_flexible_server" "main" {
  name                          = local.database_server_name
  location                      = local.database_location
  resource_group_name           = azurerm_resource_group.main.name
  version                       = local.cloud_args.database_version
  public_network_access_enabled = local.cloud_args.database_public_network_access_enabled
  administrator_login           = local.cloud_args.database_admin_username
  administrator_password        = random_password.db_password.result
  storage_mb                    = local.cloud_args.database_storage_mb
  sku_name                      = local.cloud_args.database_sku_name
  backup_retention_days         = local.cloud_args.database_backup_retention_days

  authentication {
    active_directory_auth_enabled = false
    password_auth_enabled         = true
  }
}

resource "azurerm_postgresql_flexible_server_database" "main" {
  name      = local.database_name
  server_id = azurerm_postgresql_flexible_server.main.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

resource "azurerm_private_endpoint" "postgres" {
  name                = "${local.name_prefix}-postgres-pe"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "${local.name_prefix}-postgres-psc"
    private_connection_resource_id = azurerm_postgresql_flexible_server.main.id
    is_manual_connection           = false
    subresource_names              = ["postgresqlServer"]
  }

  private_dns_zone_group {
    name                 = "postgres-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.postgres.id]
  }
}

# Users and grants are replicated from main, including the application login.
resource "azurerm_postgresql_flexible_server" "read_replica" {
  count = local.cloud_args.database_read_replica_enabled ? 1 : 0

  name                          = "${local.database_server_name}-replica"
  location                      = local.database_location
  resource_group_name           = azurerm_resource_group.main.name
  create_mode                   = "Replica"
  source_server_id              = azurerm_postgresql_flexible_server.main.id
  version                       = local.cloud_args.database_version
  sku_name                      = local.cloud_args.database_sku_name
  storage_mb                    = local.cloud_args.database_storage_mb
  public_network_access_enabled = false

  lifecycle {
    precondition {
      condition     = startswith(local.cloud_args.database_sku_name, "GP_") || startswith(local.cloud_args.database_sku_name, "MO_")
      error_message = "Azure read replicas require a General Purpose (GP_) or Memory Optimized (MO_) database_sku_name."
    }
    precondition {
      condition     = local.cloud_args.database_host == ""
      error_message = "Read replicas require the managed primary; omit azure.database_host."
    }
  }
}

resource "azurerm_private_endpoint" "postgres_read_replica" {
  count = local.cloud_args.database_read_replica_enabled ? 1 : 0

  name                = "${local.name_prefix}-postgres-replica-pe"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "${local.name_prefix}-postgres-replica-psc"
    private_connection_resource_id = azurerm_postgresql_flexible_server.read_replica[0].id
    is_manual_connection           = false
    subresource_names              = ["postgresqlServer"]
  }

  private_dns_zone_group {
    name                 = "postgres-replica-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.postgres.id]
  }
}
