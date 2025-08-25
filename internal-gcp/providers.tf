terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "6.48.0"
    }
  }
  backend "gcs" {
    bucket = "zipline-ai-tofu-state"
    prefix = "internal"
  }
}
provider "google" {
  project = "zipline-main"
  region  = "us-central1"
}