variable "orchestration" {
  description = "Shared Zipline orchestration install inputs consumed by modules/zipline-orchestration."
  type        = any

  validation {
    condition     = can(regex("^gs://[^/]+/.+", trimspace(try(var.orchestration.deployment.artifact_prefix, ""))))
    error_message = "orchestration.deployment.artifact_prefix must be a GCS URI with a path, such as gs://example-artifacts/zipline/artifacts."
  }

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{3,18}[a-z0-9]$", try(var.orchestration.deployment.customer_name, "")))
    error_message = "orchestration.deployment.customer_name must be 5-20 lowercase letters, numbers, or hyphens, start with a letter, and end with a letter or number for GCP resource naming."
  }
}

variable "gcp" {
  description = "GCP-specific orchestration wrapper inputs."
  type        = any

  validation {
    condition = alltrue([
      for key in ["project_id", "region", "warehouse_bucket"] :
      trimspace(tostring(try(var.gcp[key], ""))) != ""
    ])
    error_message = "gcp must include non-empty project_id, region, and warehouse_bucket."
  }

  validation {
    condition = (
      trimspace(tostring(try(var.gcp.network, ""))) == "" &&
      trimspace(tostring(try(var.gcp.subnetwork, ""))) == ""
      ) || (
      trimspace(tostring(try(var.gcp.network, ""))) != "" &&
      trimspace(tostring(try(var.gcp.subnetwork, ""))) != ""
    )
    error_message = "Set gcp.network and gcp.subnetwork together to use an existing network, or omit both to create one."
  }

  validation {
    condition     = !try(var.gcp.enable_private_endpoint, false) || try(var.gcp.private_nodes, true)
    error_message = "gcp.enable_private_endpoint requires gcp.private_nodes to be true."
  }


  validation {
    condition = (
      try(var.gcp.enable_private_endpoint, true) ||
      length(try(var.gcp.master_authorized_networks, [])) > 0
    )
    error_message = "When gcp.enable_private_endpoint is false, gcp.master_authorized_networks must contain at least one approved CIDR."
  }
}

resource "google_project_service" "required" {
  for_each = local.required_services

  project            = local.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "terraform_data" "configuration_validation" {
  input = {
    auth_enabled     = local.auth_enabled
    auth_secret_keys = sort(keys(local.configured_auth_secret_ids))
  }

  lifecycle {
    precondition {
      condition = !local.auth_enabled || alltrue([
        for key in local.auth_secret_keys : contains(keys(local.configured_auth_secret_ids), key)
      ])
      error_message = "When orchestration.auth.enabled is true, set every required GCP auth secret using gcp.auth_secret_ids or gcp.auth_secret_values."
    }
  }
}

module "zipline_orchestration" {
  source = "../../modules/zipline-orchestration"

  orchestration    = var.orchestration
  provider_context = local.provider_context

  depends_on = [
    google_container_node_pool.system,
    google_container_node_pool.additional,
    google_project_iam_member.workload,
    google_project_iam_member.gke_nodes,
    google_project_iam_member.workload_monitoring_viewer,
    google_secret_manager_secret_iam_member.auth_accessor,
    google_secret_manager_secret_iam_member.database_accessor,
    google_secret_manager_secret_version.database_credentials,
    google_sql_database.main,
    google_sql_user.main,
    google_storage_bucket.this,
    google_storage_bucket_iam_member.workload,
    terraform_data.configuration_validation,
  ]
}
