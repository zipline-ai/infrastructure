# A separate, opt-in release: existing shared CPU pools and team quotas are untouched.
variable "gpu_training" {
  description = "Development Ray GPU capacity. Enabling requires reviewed identity, retention and budget inputs."
  type = object({
    enabled                 = optional(bool, false)
    profile                 = optional(string, "s6e11-l40s")
    instance_type           = optional(string, "g6e.xlarge")
    availability_zones      = optional(list(string), [])
    capacity_type           = optional(string, "on-demand")
    worker_nodes            = optional(number, 1)
    multi_node_validated    = optional(bool, false)
    ami_release             = optional(string, "v20261107")
    max_deadline_seconds    = optional(number, 1800)
    retained_bucket         = optional(string, "")
    data_bucket             = optional(string, "")
    data_prefix             = optional(string, "s6e11/input/")
    controller_prefix       = optional(string, "")
    submitter_principal_arn = optional(string, "")
    kms_key_arns            = optional(list(string), [])
    glue_resource_arns      = optional(list(string), [])
  })
  default = {}
  validation {
    condition = contains(["s6e11-l40s", "s6e11-a100"], var.gpu_training.profile) && (
      (var.gpu_training.profile == "s6e11-l40s" && var.gpu_training.instance_type == "g6e.xlarge") ||
      (var.gpu_training.profile == "s6e11-a100" && var.gpu_training.instance_type == "p4d.24xlarge")
    )
    error_message = "Select s6e11-l40s/g6e.xlarge or s6e11-a100/p4d.24xlarge together; contradictory hardware selectors are rejected."
  }
  validation {
    condition     = var.gpu_training.capacity_type == "on-demand"
    error_message = "Only on-demand is validated. Spot requires a separately reviewed interruption/resume implementation."
  }
  validation {
    condition = var.gpu_training.worker_nodes == 1 || (
      var.gpu_training.worker_nodes == 2 && var.gpu_training.profile == "s6e11-a100" &&
      var.gpu_training.multi_node_validated && length(var.gpu_training.availability_zones) == 1
    )
    error_message = "Two workers require A100, exactly one AZ, and explicit multi_node_validated; EFA/NCCL is not supplied by this module."
  }
  validation {
    condition = !var.gpu_training.enabled || (
      length(var.gpu_training.availability_zones) > 0 &&
      var.gpu_training.retained_bucket != "" && var.gpu_training.data_bucket != "" &&
      can(regex("^s6e11/controllers/[a-z0-9-]+/$", var.gpu_training.controller_prefix)) &&
      can(regex("^arn:aws:iam::[0-9]{12}:(user|role)/.+$", var.gpu_training.submitter_principal_arn))
    )
    error_message = "Enabled training needs explicit AZs, retained/data buckets, a persistent s6e11/controllers/<id>/ prefix and a trusted submitter IAM principal."
  }
  validation {
    condition = (can(regex("^v[0-9]{8}$", var.gpu_training.ami_release)) &&
      var.gpu_training.max_deadline_seconds >= 60 && var.gpu_training.max_deadline_seconds <= 21600 &&
      floor(var.gpu_training.max_deadline_seconds) == var.gpu_training.max_deadline_seconds &&
    can(regex("^[a-zA-Z0-9/_-]+/$", var.gpu_training.data_prefix)))
    error_message = "Use a pinned AL2023 release, a 60–21600 second integer deadline, and a nonempty data directory prefix without wildcards."
  }
}

locals {
  gpu_namespace = "zipline-s6e11-dev"
  gpu_team      = "s6e11-dev"
  gpu_catalog = {
    s6e11-l40s = { cpu = 4, memory = 32, gpus = 1, pod_cpu = 2, pod_memory = 24, disk = "100Gi", shm = "8Gi" }
    s6e11-a100 = { cpu = 96, memory = 1152, gpus = 8, pod_cpu = 88, pod_memory = 1024, disk = "1000Gi", shm = "64Gi" }
  }
  gpu_hardware = local.gpu_catalog[var.gpu_training.profile]
  gpu_tolerations = [{
    key = "zipline.ai/workload", operator = "Equal", value = "ray-${var.gpu_training.profile}", effect = "NoSchedule"
  }, { key = "kubernetes.io/arch", operator = "Equal", value = "amd64", effect = "NoSchedule" }]
  gpu_node_pools = {
    for role in ["control", "worker"] : "${var.gpu_training.profile}-${role}" => {
      name = "${var.gpu_training.profile}-${role}"
      labels = merge({
        "zipline.ai/engine"            = "ray", "zipline.ai/role" = role,
        "zipline.ai/execution-profile" = var.gpu_training.profile
      }, role == "worker" ? { "zipline.ai/nvidia-device-plugin" = "true" } : {})
      # Node taints have no operator field (unlike Pod tolerations).
      taints       = [for t in local.gpu_tolerations : { key = t.key, value = t.value, effect = t.effect }]
      nodeClassRef = { name = "${var.gpu_training.profile}-${role}" }
      requirements = [
        { key = "kubernetes.io/os", operator = "In", values = ["linux"] },
        { key = "kubernetes.io/arch", operator = "In", values = ["amd64"] },
        { key = "karpenter.sh/capacity-type", operator = "In", values = [var.gpu_training.capacity_type] },
        { key = "node.kubernetes.io/instance-type", operator = "In", values = [role == "worker" ? var.gpu_training.instance_type : "m6i.2xlarge"] },
        { key = "topology.kubernetes.io/zone", operator = "In", values = var.gpu_training.availability_zones },
      ]
      expireAfter = "Never"
      limits = role == "worker" ? {
        cpu              = tostring(local.gpu_hardware.cpu * var.gpu_training.worker_nodes)
        memory           = "${local.gpu_hardware.memory * var.gpu_training.worker_nodes}Gi"
        "nvidia.com/gpu" = tostring(local.gpu_hardware.gpus * var.gpu_training.worker_nodes)
      } : { cpu = "8", memory = "32Gi" }
      disruption = {
        consolidationPolicy = "WhenEmpty", consolidateAfter = "1m"
        budgets             = [{ nodes = "0", reasons = ["Drifted", "Underutilized"] }, { nodes = "1", reasons = ["Empty"] }]
      }
    }
  }
  gpu_quota = {
    "limits.cpu"               = tostring(local.gpu_hardware.pod_cpu * var.gpu_training.worker_nodes + 6)
    "requests.cpu"             = tostring(local.gpu_hardware.pod_cpu * var.gpu_training.worker_nodes + 6)
    "requests.memory"          = "${local.gpu_hardware.pod_memory * var.gpu_training.worker_nodes + 16}Gi"
    "limits.memory"            = "${local.gpu_hardware.pod_memory * var.gpu_training.worker_nodes + 16}Gi"
    "requests.nvidia.com/gpu"  = tostring(local.gpu_hardware.gpus * var.gpu_training.worker_nodes)
    "count/rayjobs.ray.io"     = "1"
    "count/rayclusters.ray.io" = "1"
    pods                       = tostring(var.gpu_training.worker_nodes + 3)
  }
}

data "aws_subnet" "gpu_training" {
  count = var.gpu_training.enabled ? 2 : 0
  id    = [local.resolved_primary_subnet_id, local.resolved_secondary_subnet_id][count.index]
}

resource "helm_release" "gpu_training_nodepools" {
  count     = var.gpu_training.enabled ? 1 : 0
  name      = "s6e11-gpu-nodepools"
  chart     = "${path.module}/charts/karpenter-nodepools"
  namespace = local.karpenter.namespace
  values = [yamlencode({
    ec2NodeClasses = [for role in ["control", "worker"] : {
      name                       = "${var.gpu_training.profile}-${role}"
      amiFamily                  = "AL2023"
      amiAlias                   = "al2023@${var.gpu_training.ami_release}"
      instanceProfile            = aws_iam_instance_profile.karpenter_node[0].name
      subnetSelectorTerms        = [{ id = local.resolved_primary_subnet_id }, { id = local.resolved_secondary_subnet_id }]
      securityGroupSelectorTerms = [{ id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id }]
      metadataOptions            = { httpEndpoint = "enabled", httpTokens = "required", httpPutResponseHopLimit = 1 }
      blockDeviceMappings = [{ deviceName = "/dev/xvda", ebs = {
        volumeSize = "100Gi", volumeType = "gp3", encrypted = true,
        kmsKeyID   = aws_kms_key.eks_node_root.arn, deleteOnTermination = true
      } }]
      instanceStorePolicy = "RAID0"
    }]
    nodePools = local.gpu_node_pools
  })]
  lifecycle {
    precondition {
      condition     = alltrue([for az in var.gpu_training.availability_zones : contains(data.aws_subnet.gpu_training[*].availability_zone, az)])
      error_message = "GPU AZs must be reachable through the existing cluster's two configured subnets."
    }
    precondition {
      condition     = !contains([for ns in local.compute_namespaces : ns.name], local.gpu_namespace)
      error_message = "The GPU release owns zipline-s6e11-dev; do not also include it in shared compute.namespaces."
    }
    precondition {
      condition     = local.karpenter.enabled
      error_message = "GPU training requires the existing Karpenter installation."
    }
  }
  depends_on = [helm_release.karpenter]
}

# AL2023 NVIDIA includes the driver/runtime but not the device plugin. One release
# covers all opted-in GPU workers; no GPU Operator, GFD, NFD or time slicing.
resource "helm_release" "nvidia_device_plugin" {
  count      = var.gpu_training.enabled ? 1 : 0
  name       = "zipline-nvidia-device-plugin"
  repository = "https://nvidia.github.io/k8s-device-plugin"
  chart      = "nvidia-device-plugin"
  version    = "0.17.1"
  namespace  = "kube-system"
  values = [yamlencode({
    nodeSelector = { "zipline.ai/nvidia-device-plugin" = "true", "kubernetes.io/arch" = "amd64" }
    affinity     = null
    tolerations = [{ key = "zipline.ai/workload", operator = "Exists", effect = "NoSchedule" },
    { key = "kubernetes.io/arch", operator = "Equal", value = "amd64", effect = "NoSchedule" }]
    gfd             = { enabled = false }
    nfd             = { enabled = false }
    failOnInitError = true
    resources       = { requests = { cpu = "100m", memory = "128Mi" }, limits = { memory = "256Mi" } }
  })]
  depends_on = [aws_eks_node_group.default]
}

resource "helm_release" "gpu_training_namespace" {
  count     = var.gpu_training.enabled ? 1 : 0
  name      = "s6e11-training"
  chart     = "${path.module}/charts/gpu-training"
  namespace = local.orchestration_namespace
  values = [yamlencode({
    namespace          = local.gpu_namespace, team = local.gpu_team
    serviceAccount     = local.spark_service_account
    roleArn            = aws_iam_role.gpu_training[0].arn
    profile            = var.gpu_training.profile
    quota              = local.gpu_quota
    workerNodes        = var.gpu_training.worker_nodes
    gpus               = local.gpu_hardware.gpus
    workerCPU          = local.gpu_hardware.pod_cpu
    workerMemory       = "${local.gpu_hardware.pod_memory}Gi"
    maxDeadlineSeconds = var.gpu_training.max_deadline_seconds
    submitterGroup     = "zipline:s6e11-dev"
  })]
  depends_on = [module.zipline_orchestration]
}
