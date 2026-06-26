variable "orchestration" {
  description = "Shared Zipline orchestration install inputs consumed by modules/zipline-orchestration."
  type        = any
}

variable "azure" {
  description = "Azure-specific orchestration wrapper inputs."
  type        = any
}

provider "azurerm" {
  features {}

  subscription_id = local.cloud_args.subscription_id
}

data "azurerm_kubernetes_cluster" "this" {
  name                = local.cloud_args.aks_cluster_name
  resource_group_name = local.cloud_args.aks_resource_group
}

provider "kubernetes" {
  host                   = local.kubernetes_provider.host
  cluster_ca_certificate = local.kubernetes_provider.cluster_ca_certificate
  token                  = local.kubernetes_provider.token
  client_certificate     = local.kubernetes_provider.client_certificate
  client_key             = local.kubernetes_provider.client_key
}

provider "helm" {
  kubernetes {
    host                   = local.kubernetes_provider.host
    cluster_ca_certificate = local.kubernetes_provider.cluster_ca_certificate
    token                  = local.kubernetes_provider.token
    client_certificate     = local.kubernetes_provider.client_certificate
    client_key             = local.kubernetes_provider.client_key
  }
}

module "zipline_orchestration" {
  source = "../../modules/zipline-orchestration"

  orchestration = local.orchestration
}
