// Provider configuration
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket         = "zipline-ai-opentofu-state-bucket"
    key            = "opentofu-k8s-canary-state"
    region         = var.region
  }
}

provider "aws" {
  region = var.region
  profile = "default"

}

data "aws_eks_cluster" "zipline_canary_eks" {
  name = "Zipline-Canary-EKS"
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.zipline_canary_eks.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.zipline_canary_eks.certificate_authority[0].data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", data.aws_eks_cluster.zipline_canary_eks.name]
    command     = "aws"
  }
}