# Optional request generators owned by this deployment. Keep deployment-specific
# images, join names and schedules in private tfvars, not in the public module.
resource "kubernetes_manifest" "request_jobs" {
  for_each = try(var.aws.request_jobs, {})

  manifest = {
    apiVersion = "batch/v1"
    kind       = "CronJob"
    metadata = {
      name      = each.key
      namespace = local.orchestration_namespace
    }
    spec = each.value
  }
}
