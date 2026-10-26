variable "orchestration" {
  description = "Shared Zipline orchestration install inputs consumed by modules/zipline-orchestration."
  type        = any
}

variable "gcp" {
  description = "GCP-specific orchestration wrapper inputs."
  type        = any

  validation {
    condition = alltrue([
      for key in [
        "project_id",
        "region",
        "warehouse_bucket",
      ] : trimspace(tostring(try(var.gcp[key], ""))) != ""
    ])
    error_message = "gcp must include non-empty project_id, region, and warehouse_bucket."
  }

  # network/subnet are provisioned on the fly when omitted (see network.tf);
  # supply both together to bring your own VPC.
  validation {
    condition = (
      length(compact([
        trimspace(tostring(try(var.gcp.network, ""))),
        trimspace(tostring(try(var.gcp.subnet, ""))),
      ])) == 0
      ) || (
      trimspace(tostring(try(var.gcp.network, ""))) != "" &&
      trimspace(tostring(try(var.gcp.subnet, ""))) != ""
    )
    error_message = "Set gcp.network and gcp.subnet together to use an existing network, or omit both to have Terraform create one."
  }
}

# Mirrors AWS's terraform_data.configuration_validation (aws/main.tf:52-56):
# fail at plan when auth.enabled=true but the Secret Manager secret id is not a
# recognizable form. Catches a tfvars typo before helm install.
resource "terraform_data" "configuration_validation" {
  input = {
    auth_enabled   = local.auth_enabled
    auth_secret_id = local.auth_secret_id
  }

  lifecycle {
    precondition {
      condition = (
        !local.auth_enabled ||
        can(regex("^projects/[^/]+/secrets/[^/]+$", local.auth_secret_id)) ||
        can(regex("^[A-Za-z0-9_-]+$", local.auth_secret_id))
      )
      error_message = "When auth.enabled is true, set gcp.auth_secret_id or orchestration.auth.secrets_arn to a Secret Manager id (projects/<project>/secrets/<name> or a bare id)."
    }
  }
}

module "zipline_orchestration" {
  source = "../../modules/zipline-orchestration"

  orchestration    = local.module_orchestration
  provider_context = local.provider_context

  depends_on = [
    google_container_node_pool.pools,
    google_project_iam_member.orchestration,
    google_project_iam_member.spark,
    google_project_iam_member.flink,
    google_project_iam_member.eval,
    google_service_account_iam_member.orchestration_wi,
    google_service_account_iam_member.spark_wi,
    google_service_account_iam_member.flink_wi,
    google_service_account_iam_member.eval_wi,
    google_service_account_iam_member.polaris_wi,
    google_service_account_iam_member.external_secrets_wi,
    google_secret_manager_secret_version.db_credentials,
    google_sql_database.execution_info,
    google_bigtable_app_profile.groupby_ingest,
    google_storage_bucket_object.spark_events_prefix,
    terraform_data.configuration_validation,
  ]
}
