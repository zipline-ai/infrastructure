data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "main" {
  name                       = local.keyvault_name
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = local.tenant_id
  sku_name                   = "standard"
  enable_rbac_authorization  = true
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
}

data "azuread_user" "tf_admins" {
  for_each            = toset(local.cloud_args.admin_principal_names)
  user_principal_name = each.value
}

resource "azuread_group" "tf_admins" {
  display_name     = "${local.name_prefix}-tf-admins"
  security_enabled = true

  members = [
    for user in data.azuread_user.tf_admins : user.object_id
  ]
}


resource "azurerm_role_assignment" "terraform_keyvault_secrets_officer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = azuread_group.tf_admins.object_id
  principal_type       = "Group"
}

resource "azurerm_role_assignment" "workload_keyvault_secrets_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.workload.principal_id
}

resource "random_password" "db_password" {
  length  = 24
  special = true
}

resource "azurerm_key_vault_secret" "db_username" {
  name         = local.cloud_args.database_username_secret_name
  value        = local.cloud_args.database_admin_username
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.terraform_keyvault_secrets_officer]
}

resource "azurerm_key_vault_secret" "db_password" {
  name         = local.cloud_args.database_password_secret_name
  value        = random_password.db_password.result
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.terraform_keyvault_secrets_officer]
}
