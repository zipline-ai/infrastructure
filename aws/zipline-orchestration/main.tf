variable "orchestration" {
  description = "Shared Zipline orchestration install inputs consumed by modules/zipline-orchestration."
  type        = any
}

variable "aws" {
  description = "AWS-specific orchestration wrapper inputs."
  type        = any

  validation {
    condition     = !try(var.orchestration.auth.enabled, false) || trimspace(try(var.aws.auth_secret_arn, "")) != ""
    error_message = "auth_secret_arn must be set when auth.enabled is true."
  }
}

provider "aws" {
  region              = local.cloud_args.region
  allowed_account_ids = local.cloud_args.account_id == "" ? null : [local.cloud_args.account_id]
}

data "aws_eks_cluster" "this" {
  name = local.cloud_args.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = local.cloud_args.cluster_name
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
