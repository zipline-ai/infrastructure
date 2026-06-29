provider "azurerm" {
  subscription_id = local.cloud_args.subscription_id != "" ? local.cloud_args.subscription_id : null

  features {}
}
