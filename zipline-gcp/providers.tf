terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "6.14.1"
    }
  }
}
provider "google" {
  project = var.project
  region  = var.region
}