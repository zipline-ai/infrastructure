terraform {
  required_version = ">= 1.9.0"

  backend "azurerm" {}

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.13.0, < 3.0.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.29.0"
    }
  }
}
