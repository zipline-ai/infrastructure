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
    key    = "opentofu-internal-state"
    region = var.region
  }
}

provider "aws" {
  region  = var.region
  profile = "default"

}