locals {
  fetcher_cosmos_account_name = local.cloud_args.fetcher_cosmos_account_name != "" ? local.cloud_args.fetcher_cosmos_account_name : "${local.name_prefix}-zipline-kv"
}

resource "azurerm_cosmosdb_account" "fetcher" {
  count = local.deploy_fetcher ? 1 : 0

  name                          = local.fetcher_cosmos_account_name
  location                      = azurerm_resource_group.main.location
  resource_group_name           = azurerm_resource_group.main.name
  offer_type                    = "Standard"
  kind                          = "GlobalDocumentDB"
  public_network_access_enabled = false

  capabilities {
    name = "EnableServerless"
  }

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = azurerm_resource_group.main.location
    failover_priority = 0
  }
}

resource "azurerm_cosmosdb_sql_database" "fetcher" {
  count = local.deploy_fetcher ? 1 : 0

  name                = local.cloud_args.fetcher_cosmos_database
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.fetcher[0].name
}

# Containers - Batch Tables (multi-level partition: /dataset and /keyHash)
resource "azurerm_cosmosdb_sql_container" "groupby_batch" {
  count = local.deploy_fetcher ? 1 : 0
  name                  = "groupby_batch"
  resource_group_name   = azurerm_resource_group.main.name
  account_name          = azurerm_cosmosdb_account.fetcher[0].name
  database_name         = azurerm_cosmosdb_sql_database.fetcher[0].name
  partition_key_paths   = ["/dataset", "/keyHash"]
  partition_key_kind    = "MultiHash"
  partition_key_version = 2
  default_ttl           = 432000 # 120h = 5 days in seconds
}

# Containers - Streaming Tables (multi-level partition: /dataset and /keyHashDay)
resource "azurerm_cosmosdb_sql_container" "groupby_streaming" {
  count = local.deploy_fetcher ? 1 : 0
  name                  = "groupby_streaming"
  resource_group_name   = azurerm_resource_group.main.name
  account_name          = azurerm_cosmosdb_account.fetcher[0].name
  database_name         = azurerm_cosmosdb_sql_database.fetcher[0].name
  partition_key_paths   = ["/dataset", "/keyHashDay"]
  partition_key_kind    = "MultiHash"
  partition_key_version = 2
  default_ttl           = 432000
}

# Containers - Metadata Tables (single partition: /keyHash)
resource "azurerm_cosmosdb_sql_container" "chronon_metadata" {
  count = local.deploy_fetcher ? 1 : 0
  name                  = "chronon_metadata"
  resource_group_name   = azurerm_resource_group.main.name
  account_name          = azurerm_cosmosdb_account.fetcher[0].name
  database_name         = azurerm_cosmosdb_sql_database.fetcher[0].name
  partition_key_paths   = ["/keyHash"]
  partition_key_version = 2
  default_ttl           = 432000
}

resource "azurerm_cosmosdb_sql_container" "enhanced_stats" {
  count = local.deploy_fetcher ? 1 : 0
  name                  = "enhanced_stats"
  resource_group_name   = azurerm_resource_group.main.name
  account_name          = azurerm_cosmosdb_account.fetcher[0].name
  database_name         = azurerm_cosmosdb_sql_database.fetcher[0].name
  partition_key_paths   = ["/keyHash"]
  partition_key_version = 2
  default_ttl           = 63072000 # 2 years in seconds
}

resource "azurerm_cosmosdb_sql_container" "data_quality_metrics_batch" {
  count = local.deploy_fetcher ? 1 : 0
  name                  = "data_quality_metrics_batch"
  resource_group_name   = azurerm_resource_group.main.name
  account_name          = azurerm_cosmosdb_account.fetcher[0].name
  database_name         = azurerm_cosmosdb_sql_database.fetcher[0].name
  partition_key_paths   = ["/keyHash"]
  partition_key_version = 2
  default_ttl           = 63072000 # 2 years in seconds
}

resource "azurerm_cosmosdb_sql_container" "table_partitions" {
  count = local.deploy_fetcher ? 1 : 0
  name                  = "table_partitions"
  resource_group_name   = azurerm_resource_group.main.name
  account_name          = azurerm_cosmosdb_account.fetcher[0].name
  database_name         = azurerm_cosmosdb_sql_database.fetcher[0].name
  partition_key_paths   = ["/keyHash"]
  partition_key_version = 2
  default_ttl           = 432000
}

resource "azurerm_private_dns_zone" "cosmos" {
  count = local.deploy_fetcher ? 1 : 0

  name                = "privatelink.documents.azure.com"
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "cosmos" {
  count = local.deploy_fetcher ? 1 : 0

  name                  = "${local.cluster_name}-cosmos"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.cosmos[0].name
  virtual_network_id    = azurerm_virtual_network.main.id
}

resource "azurerm_private_endpoint" "cosmos" {
  count = local.deploy_fetcher ? 1 : 0

  name                = "${local.name_prefix}-cosmos-pe"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "${local.name_prefix}-cosmos-psc"
    private_connection_resource_id = azurerm_cosmosdb_account.fetcher[0].id
    is_manual_connection           = false
    subresource_names              = ["Sql"]
  }

  private_dns_zone_group {
    name                 = "cosmos-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.cosmos[0].id]
  }
}

resource "azurerm_key_vault_secret" "fetcher_cosmos_key" {
  count = local.deploy_fetcher ? 1 : 0

  name         = "${local.name_prefix}-cosmos-primary-key"
  value        = azurerm_cosmosdb_account.fetcher[0].primary_key
  key_vault_id = local.keyvault_id

  depends_on = [azurerm_role_assignment.terraform_keyvault_secrets_officer]
}
