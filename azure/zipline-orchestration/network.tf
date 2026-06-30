resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = local.cloud_args.location
}

resource "azurerm_virtual_network" "main" {
  name                = "${local.name_prefix}-zipline-vnet"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = local.cloud_args.vnet_address_space
}

resource "azurerm_subnet" "aks" {
  name                 = "${local.name_prefix}-aks-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = local.cloud_args.aks_subnet_address_prefixes
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = "${local.name_prefix}-private-endpoints-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [local.cloud_args.private_endpoints_subnet_address_prefix]
}

