locals {
  # Compute capacity is shared across namespaces. Team budgets are enforced by
  # ResourceQuota; adding a namespace must not add another set of NodePools.
  compute_node_pool_workloads = [
    { engine = "spark", role = "driver", size = "driver" },
    { engine = "spark", role = "executor", size = "executor" },
    { engine = "flink", role = "jobmanager", size = "driver" },
    { engine = "flink", role = "taskmanager", size = "executor" },
  ]
  system_node_pool        = "system"
  image_prepull_node_pool = "spark-executor"
  system_node_selector = local.karpenter.enabled ? {
    "zipline.ai/node-pool" = local.system_node_pool
  } : {}
  image_prepull_node_selector = local.karpenter.enabled ? {
    "zipline.ai/engine" = "spark"
    "zipline.ai/role"   = "executor"
  } : {}
  system_node_tolerations = local.karpenter.enabled ? [
    {
      key      = "zipline.ai/node-pool"
      operator = "Equal"
      value    = local.system_node_pool
      effect   = "NoSchedule"
    }
  ] : []
  image_prepull_node_tolerations = local.karpenter.enabled ? [
    {
      key      = "zipline.ai/workload"
      operator = "Equal"
      value    = local.image_prepull_node_pool
      effect   = "NoSchedule"
    }
  ] : []
  karpenter_node_pool_requirements = [
    {
      key      = "kubernetes.io/os"
      operator = "In"
      values   = ["linux"]
    },
    {
      key      = "kubernetes.io/arch"
      operator = "In"
      values   = ["amd64"]
    },
    {
      key      = "karpenter.sh/capacity-type"
      operator = "In"
      values   = ["on-demand"]
    },
    {
      key      = "karpenter.k8s.aws/instance-category"
      operator = "In"
      values   = ["c", "m", "r"]
    },
    {
      key      = "karpenter.k8s.aws/instance-generation"
      operator = "Gt"
      values   = ["2"]
    },
  ]
  # ───────────────────────────────────────────────────────────────────────
  # Karpenter tunables — override any of these via aws.karpenter.<key> in the
  # tfvars. All optional; the defaults shown here apply when unset. The
  # instance-shape knobs (arch / categories / capacity / generation / minValues)
  # build the driver & executor pool requirements below.
  #   aws.karpenter.driver_arch              (default ["arm64"])
  #   aws.karpenter.driver_categories        (default ["m"])
  #   aws.karpenter.executor_arch            (default ["arm64"])
  #   aws.karpenter.executor_categories      (default ["c","m","r"])
  #   aws.karpenter.executor_capacity_type   (default ["spot"])
  #   aws.karpenter.executor_min_categories  (default 2)     # spot diversity
  #   aws.karpenter.min_instance_generation  (default "6")   # 7th-gen+
  #   aws.karpenter.pool_limits/driver_limits/executor_limits  ({cpu,memory})
  #   aws.karpenter.system_expire_after / compute_expire_after
  #   aws.karpenter.system_termination_grace_period
  # ───────────────────────────────────────────────────────────────────────
  karpenter_driver_arch         = tolist(try(local.karpenter.driver_arch, ["arm64"]))
  karpenter_driver_categories   = tolist(try(local.karpenter.driver_categories, ["m"]))
  karpenter_executor_arch       = tolist(try(local.karpenter.executor_arch, ["arm64"]))
  karpenter_executor_categories = tolist(try(local.karpenter.executor_categories, ["c", "m", "r"]))
  karpenter_executor_capacity   = tolist(try(local.karpenter.executor_capacity_type, ["spot"]))
  karpenter_executor_min_values = try(local.karpenter.executor_min_categories, 2)
  karpenter_min_generation      = try(local.karpenter.min_instance_generation, "6")
  # Provisioning caps (max aggregate a pool may launch); memory cap alongside
  # cpu so a runaway pool can't exhaust either. Role-sized: drivers small,
  # executors fat. Each cap covers all teams sharing that engine/role pool.
  karpenter_pool_limits             = merge({ cpu = "1000", memory = "4000Gi" }, try(local.karpenter.pool_limits, {}))
  karpenter_driver_limits           = merge({ cpu = "100", memory = "400Gi" }, try(local.karpenter.driver_limits, {}))
  karpenter_executor_limits         = merge({ cpu = "1000", memory = "4000Gi" }, try(local.karpenter.executor_limits, {}))
  karpenter_driver_instance_types   = tolist(try(local.karpenter.driver_instance_types, []))
  karpenter_executor_instance_types = tolist(try(local.karpenter.executor_instance_types, []))
  # Driver pool: on-demand — drivers are lightweight (1/job) and must NOT run on
  # spot (a spot eviction kills the whole job).
  karpenter_driver_requirements = [
    { key = "kubernetes.io/os", operator = "In", values = tolist(["linux"]) },
    { key = "kubernetes.io/arch", operator = "In", values = local.karpenter_driver_arch },
    { key = "karpenter.sh/capacity-type", operator = "In", values = tolist(["on-demand"]) },
    { key = "karpenter.k8s.aws/instance-category", operator = "In", values = local.karpenter_driver_categories, minValues = null },
    { key = "karpenter.k8s.aws/instance-generation", operator = "Gt", values = tolist([local.karpenter_min_generation]) },
  ]
  # Executor pool: spot by default — the compute; spot decommission migrates
  # shuffle. minValues forces instance-type diversity for spot availability.
  karpenter_executor_requirements = [
    { key = "kubernetes.io/os", operator = "In", values = tolist(["linux"]) },
    { key = "kubernetes.io/arch", operator = "In", values = local.karpenter_executor_arch },
    { key = "karpenter.sh/capacity-type", operator = "In", values = local.karpenter_executor_capacity },
    { key = "karpenter.k8s.aws/instance-category", operator = "In", values = local.karpenter_executor_categories, minValues = local.karpenter_executor_min_values },
    { key = "karpenter.k8s.aws/instance-generation", operator = "Gt", values = tolist([local.karpenter_min_generation]) },
  ]
  karpenter_spark_executor_instance_store_requirements = [
    { key = "karpenter.k8s.aws/instance-local-nvme", operator = "Exists", values = null, minValues = null },
  ]
  # The system pool hosts stateful control-plane pods (loki + spark-history
  # PVCs, polaris). Default to no forced node rotation and a real drain grace
  # period so a rotation doesn't strand a PVC in the wrong AZ or cut loki off
  # mid-flush. Compute pools keep the 30-day recycle. All configurable.
  karpenter_system_expire_after             = try(local.karpenter.system_expire_after, "Never")
  karpenter_system_termination_grace_period = try(local.karpenter.system_termination_grace_period, "5m")
  karpenter_compute_expire_after            = try(local.karpenter.compute_expire_after, "720h")
  compute_node_pool_matrix = [
    for workload in local.compute_node_pool_workloads : {
      key            = "${workload.engine}-${workload.role}"
      engine         = workload.engine
      role           = workload.role
      size           = workload.size
      instance_store = workload.engine == "spark" && workload.role == "executor"
      limits         = workload.size == "driver" ? local.karpenter_driver_limits : local.karpenter_executor_limits
      instance_types = workload.size == "driver" ? local.karpenter_driver_instance_types : local.karpenter_executor_instance_types
      taints = [
        {
          key      = "zipline.ai/workload"
          operator = "Equal"
          value    = "${workload.engine}-${workload.role}"
          effect   = "NoSchedule"
        }
      ]
    }
  ]
  karpenter_system_node_pool = {
    system = {
      enabled = true
      name    = local.system_node_pool
      labels = {
        "zipline.ai/team"      = "system"
        "zipline.ai/node-pool" = local.system_node_pool
      }
      taints                 = local.system_node_tolerations
      requirements           = local.karpenter_node_pool_requirements
      expireAfter            = local.karpenter_system_expire_after
      terminationGracePeriod = local.karpenter_system_termination_grace_period
      limits                 = local.karpenter_pool_limits
      disruption = {
        # Only reclaim genuinely-empty nodes. WhenEmptyOrUnderutilized would
        # drain still-in-use nodes, disrupting running Spark executors / Flink
        # taskmanagers and stateful control-plane pods (loki, spark-history);
        # the platform submitter does not set karpenter.sh/do-not-disrupt.
        consolidationPolicy = "WhenEmpty"
        consolidateAfter    = "1m"
      }
    }
  }
  karpenter_compute_node_pools = {
    for pool in local.compute_node_pool_matrix :
    pool.key => {
      enabled = true
      name    = pool.key
      labels = {
        "zipline.ai/engine"   = pool.engine
        "zipline.ai/role"     = pool.role
        "zipline.ai/workload" = pool.key
      }
      taints = pool.taints
      requirements = concat(
        # Pinning explicit instance types REPLACES the category/generation selector
        # (Karpenter ANDs requirements, so keeping both would narrow to empty and
        # never provision); os/arch/capacity-type still apply.
        [for r in(pool.size == "driver" ? local.karpenter_driver_requirements : local.karpenter_executor_requirements) :
        r if length(pool.instance_types) == 0 || !contains(["karpenter.k8s.aws/instance-category", "karpenter.k8s.aws/instance-generation"], r.key)],
        length(pool.instance_types) > 0 ? [{ key = "node.kubernetes.io/instance-type", operator = "In", values = pool.instance_types, minValues = null }] : [],
        pool.instance_store ? local.karpenter_spark_executor_instance_store_requirements : [],
      )
      expireAfter = local.karpenter_compute_expire_after
      limits      = pool.limits
      disruption = {
        # Only reclaim genuinely-empty nodes. WhenEmptyOrUnderutilized would
        # drain still-in-use nodes, disrupting running Spark executors / Flink
        # taskmanagers and stateful control-plane pods (loki, spark-history);
        # the platform submitter does not set karpenter.sh/do-not-disrupt.
        consolidationPolicy = "WhenEmpty"
        consolidateAfter    = "1m"
      }
    }
  }
  karpenter_default_node_pools = merge(
    local.karpenter_system_node_pool,
    local.karpenter_compute_node_pools,
  )
  karpenter_node_pool_inputs = {
    for key, pool in merge(local.karpenter_default_node_pools, try(local.karpenter.node_pools, {})) :
    key => merge(try(local.karpenter_default_node_pools[key], {}), pool)
  }
  karpenter_node_pools = {
    for key, pool in local.karpenter_node_pool_inputs :
    key => pool
    if local.karpenter.enabled && try(pool.enabled, true)
  }

  # Reuse the shared Spark driver's placement for pre-warmed capacity.
  compute_warm_pool = {
    enabled      = local.karpenter.enabled
    nodeSelector = local.karpenter_compute_node_pools["spark-driver"].labels
    tolerations  = local.karpenter_compute_node_pools["spark-driver"].taints
  }
}
