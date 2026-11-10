output "gpu_training_integration" {
  description = "Non-secret integration contract. Non-null only after enabling; verify live GPU smoke checks separately."
  value = !var.gpu_training.enabled ? null : {
    cluster                 = local.cluster_name
    account                 = data.aws_caller_identity.current.account_id
    region                  = local.cloud_args.region
    namespace               = local.gpu_namespace
    team                    = local.gpu_team
    service_account         = local.spark_service_account
    workload_role           = aws_iam_role.gpu_training[0].arn
    submitter_role          = aws_iam_role.gpu_submitter[0].arn
    profile                 = var.gpu_training.profile
    node_pools              = local.gpu_node_pools
    namespace_quota         = local.gpu_quota
    data_root               = "s3://${var.gpu_training.data_bucket}/${var.gpu_training.data_prefix}"
    model_artifact_base_uri = "s3://${var.gpu_training.retained_bucket}/${trimsuffix(var.gpu_training.controller_prefix, "/")}"
    run_root                = "s3://${var.gpu_training.retained_bucket}/${var.gpu_training.controller_prefix}runs/"
    local_hub_env = {
      CRUCIBLE_RAY_GPU_PROFILES      = var.gpu_training.profile
      CRUCIBLE_EXECUTION_REGION      = local.cloud_args.region
      CRUCIBLE_DEFAULT_NAMESPACE     = local.gpu_namespace
      CRUCIBLE_SPARK_SERVICE_ACCOUNT = local.spark_service_account
    }
    ray_conf = {
      "ray.placement.profile"        = var.gpu_training.profile
      "ray.architecture"             = "amd64"
      "ray.worker.replicas"          = tostring(var.gpu_training.worker_nodes)
      "ray.worker.gpus"              = tostring(local.gpu_hardware.gpus)
      "ray.worker.cpu"               = tostring(local.gpu_hardware.pod_cpu)
      "ray.worker.memory"            = "${local.gpu_hardware.pod_memory}Gi"
      "ray.worker.ephemeral-storage" = local.gpu_hardware.disk
      "ray.worker.shm"               = local.gpu_hardware.shm
      "ray.head.cpu"                 = "2"
      "ray.head.memory"              = "8Gi"
      "ray.timeout.seconds"          = tostring(var.gpu_training.max_deadline_seconds)
      "ray.region"                   = local.cloud_args.region
    }
    runtime = { ray = "2.55.1", kuberay = "1.7.0", device_plugin = "0.17.1", ami = "al2023@${var.gpu_training.ami_release}" }
  }
}
