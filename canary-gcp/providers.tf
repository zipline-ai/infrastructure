terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "6.14.1"
    }
  }
  backend "gcs" {
    bucket = "zipline-ai-tofu-state"
    prefix = "canary"
  }
}
provider "google" {
  project = "canary-443022"
  region  = "us-central1"
}