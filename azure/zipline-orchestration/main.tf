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

  subscription_id = local.azure.subscription_id
}

data "azurerm_kubernetes_cluster" "this" {
  name                = local.azure.aks_cluster_name
  resource_group_name = local.azure.aks_resource_group
}

provider "kubernetes" {
  host                   = data.azurerm_kubernetes_cluster.this.kube_config[0].host
  client_certificate     = base64decode(data.azurerm_kubernetes_cluster.this.kube_config[0].client_certificate)
  client_key             = base64decode(data.azurerm_kubernetes_cluster.this.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = data.azurerm_kubernetes_cluster.this.kube_config[0].host
    client_certificate     = base64decode(data.azurerm_kubernetes_cluster.this.kube_config[0].client_certificate)
    client_key             = base64decode(data.azurerm_kubernetes_cluster.this.kube_config[0].client_key)
    cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate)
  }
}

module "zipline_orchestration" {
  source = "../../modules/zipline-orchestration"

  chart_path    = abspath("${path.module}/../../charts/zipline-orchestration")
  orchestration = merge(local.orchestration, { values = local.provider_values })
}
