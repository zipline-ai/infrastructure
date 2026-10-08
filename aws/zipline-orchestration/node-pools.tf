locals {
  # Compute capacity is shared across namespaces. Team budgets are enforced by
  # ResourceQuota; adding a namespace must not add another set of NodePools.
  system_node_pool = "system"
  system_node_selector = local.karpenter.enabled ? {
    "zipline.ai/node-pool" = local.system_node_pool
  } : {}
  image_prepull_node_selector = local.karpenter.enabled ? {
    "zipline.ai/engine" = "spark"
  } : {}
  image_prepull_affinity = local.karpenter.enabled ? {
    nodeAffinity = {
      requiredDuringSchedulingIgnoredDuringExecution = {
        nodeSelectorTerms = [{
          matchExpressions = [{
            key      = "karpenter.k8s.aws/instance-local-nvme"
            operator = "Exists"
          }]
        }]
      }
    }
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
      value    = "spark"
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
  karpenter_compute_arch           = tolist(try(local.karpenter.compute_arch, ["arm64"]))
  karpenter_compute_categories     = tolist(try(local.karpenter.compute_categories, ["c", "m", "r"]))
  karpenter_compute_instance_types = tolist(try(local.karpenter.compute_instance_types, []))
  karpenter_min_generation         = try(local.karpenter.min_instance_generation, "6")
  # Each compute cap covers all roles and teams using that engine.
  karpenter_pool_limits    = merge({ cpu = "1000", memory = "4000Gi" }, try(local.karpenter.pool_limits, {}))
  karpenter_compute_limits = merge({ cpu = "1100", memory = "4400Gi" }, try(local.karpenter.compute_limits, {}))
  # Shared hardware requirements; pods add role-specific requirements such as
  # Spark executor NVMe. Capacity types are set per engine below.
  karpenter_compute_requirements = [
    { key = "kubernetes.io/os", operator = "In", values = tolist(["linux"]) },
    { key = "kubernetes.io/arch", operator = "In", values = local.karpenter_compute_arch },
    { key = "karpenter.k8s.aws/instance-category", operator = "In", values = local.karpenter_compute_categories },
    { key = "karpenter.k8s.aws/instance-generation", operator = "Gt", values = tolist([local.karpenter_min_generation]) },
  ]
  # The system pool hosts stateful control-plane pods (loki + spark-history
  # PVCs, polaris). Default to no forced node rotation and a real drain grace
  # period so a rotation doesn't strand a PVC in the wrong AZ or cut loki off
  # mid-flush. Compute pools keep the 30-day recycle. All configurable.
  karpenter_system_expire_after             = try(local.karpenter.system_expire_after, "Never")
  karpenter_system_termination_grace_period = try(local.karpenter.system_termination_grace_period, "5m")
  karpenter_compute_expire_after            = try(local.karpenter.compute_expire_after, "720h")
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
    for engine in ["spark", "flink"] :
    engine => {
      enabled = true
      name    = engine
      labels = {
        "zipline.ai/engine"   = engine
        "zipline.ai/workload" = engine
      }
      taints = [{
        key      = "zipline.ai/workload"
        operator = "Equal"
        value    = engine
        effect   = "NoSchedule"
      }]
      requirements = concat(
        [{
          key      = "karpenter.sh/capacity-type"
          operator = "In"
          values   = engine == "spark" ? ["on-demand", "spot"] : ["on-demand"]
        }],
        # Pinning explicit instance types REPLACES the category/generation selector
        # (Karpenter ANDs requirements, so keeping both would narrow to empty and
        # never provision); os/arch/capacity-type still apply.
        [for r in local.karpenter_compute_requirements :
        r if length(local.karpenter_compute_instance_types) == 0 || !contains(["karpenter.k8s.aws/instance-category", "karpenter.k8s.aws/instance-generation"], r.key)],
        length(local.karpenter_compute_instance_types) > 0 ? [{ key = "node.kubernetes.io/instance-type", operator = "In", values = local.karpenter_compute_instance_types }] : [],
      )
      expireAfter = local.karpenter_compute_expire_after
      limits      = merge(local.karpenter_compute_limits, try(local.karpenter["${engine}_limits"], {}))
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

  # Pre-warm on-demand Spark capacity without constraining instance storage.
  compute_warm_pool = {
    enabled = local.karpenter.enabled
    nodeSelector = {
      "zipline.ai/engine"          = "spark"
      "karpenter.sh/capacity-type" = "on-demand"
    }
    tolerations = local.karpenter_compute_node_pools["spark"].taints
  }
}
