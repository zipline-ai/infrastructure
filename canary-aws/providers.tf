// Provider configuration
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket = "zipline-ai-opentofu-state-bucket"
    key    = "opentofu-canary-state"
    region = var.region
  }
}

provider "aws" {
  region  = var.region
  profile = "default"

}

# provider "kubernetes" {
#   host                   = aws_eks_cluster.zipline_canary_eks.endpoint
#   cluster_ca_certificate = base64decode(aws_eks_cluster.zipline_canary_eks.certificate_authority[0].data)
#   exec {
#     api_version = "client.authentication.k8s.io/v1beta1"
#     args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.zipline_canary_eks.name]
#     command     = "aws"
#   }
# }

module "base_setup" {
  source = "../base-aws"

  name = "Canary"
}

output "frontend_url" {
  value = module.base_setup.frontend_url
}