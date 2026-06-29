terraform {
  required_version = ">= 1.9.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.19"
    }
  }
}

variable "api_token" {
  description = "Cloudflare API token with DNS edit permissions for the zone."
  type        = string
  sensitive   = true
}

variable "zone_id" {
  description = "Cloudflare zone ID."
  type        = string
}

variable "record_name" {
  description = "DNS record name."
  type        = string
}

variable "target" {
  description = "CNAME target."
  type        = string
}

provider "cloudflare" {
  api_token = var.api_token
}

resource "cloudflare_dns_record" "public_host" {
  zone_id = var.zone_id
  name    = var.record_name
  type    = "CNAME"
  content = var.target
  ttl     = 1
  proxied = false

  lifecycle {
    precondition {
      condition     = var.zone_id != ""
      error_message = "zone_id must be set."
    }
    precondition {
      condition     = var.api_token != ""
      error_message = "api_token must be set."
    }
    precondition {
      condition     = var.record_name != ""
      error_message = "record_name must be set."
    }
    precondition {
      condition     = var.target != ""
      error_message = "target must be set."
    }
  }
}

output "record_name" {
  description = "Managed DNS record name."
  value       = cloudflare_dns_record.public_host.name
}
