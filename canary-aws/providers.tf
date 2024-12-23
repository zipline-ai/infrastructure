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
    key            = "opentofu-canary-state"
    region         = var.region
  }
}
 
provider "aws" {
 region = var.region
 profile = "default"

}

module "base_setup" {
  source = "../base-aws"

  name = "Canary"
}

output "eks_cluster_name" {
  value = module.base_setup.eks_cluster_name
}