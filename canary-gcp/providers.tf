terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "6.48.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.5.3"
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

provider "local" {}