variable "orchestration" {
  description = "Shared Zipline orchestration install inputs consumed by modules/zipline-orchestration."
  type        = any
}

variable "aws" {
  description = "AWS-specific orchestration wrapper inputs."
  type        = any
}

provider "aws" {
  region              = local.aws.region
  allowed_account_ids = local.aws.account_id == "" ? null : [local.aws.account_id]
}

data "aws_eks_cluster" "this" {
  name = local.aws.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = local.aws.cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

resource "terraform_data" "configuration_validation" {
  input = {
    auth_enabled = local.auth_enabled
  }

  lifecycle {
    precondition {
      condition     = !local.auth_enabled || trimspace(local.aws.auth_secret_arn) != ""
      error_message = "auth_secret_arn must be set when auth.enabled is true."
    }
  }
}

module "zipline_orchestration" {
  source = "../../modules/zipline-orchestration"

  orchestration = local.orchestration
}
