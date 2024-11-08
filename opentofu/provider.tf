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
    key            = "opentofu-state"
    region         = "us-west-1"
  }
}
 
provider "aws" {
 region = var.region
 profile = "default"

}

provider "kubernetes" {
  host                   = aws_eks_cluster.zipline_demo_eks.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.zipline_demo_eks.certificate_authority[0].data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.zipline_demo_eks.name]
    command     = "aws"
  }
}