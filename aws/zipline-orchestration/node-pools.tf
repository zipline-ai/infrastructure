locals {
  # Compute capacity is shared across namespaces. Team budgets are enforced by
  # ResourceQuota; adding a namespace must not add another set of NodePools.
  system_node_pool = "system"
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
  # Optional common limits override each pool's defaults; per-pool limits win.
  karpenter_pool_limits    = merge({ cpu = "1000", memory = "4000Gi" }, try(local.karpenter.pool_limits, {}))
  karpenter_compute_limits = try(local.karpenter.compute_limits, {})
  karpenter_compute_pool_defaults = {
    spark-driver = {
      engine        = "spark"
      role          = "driver"
      capacity_type = "on-demand"
      limits        = { cpu = "100", memory = "400Gi" }
    }
    spark-executor = {
      engine        = "spark"
      role          = "executor"
      capacity_type = "spot"
      limits        = { cpu = "1000", memory = "4000Gi" }
    }
    flink = {
      engine        = "flink"
      role          = null
      capacity_type = "on-demand"
      limits        = { cpu = "1100", memory = "4400Gi" }
    }
    # Ray training. Shared across teams, same as the Spark and Flink pools.
    # On-demand for both roles, unlike spark-executor: training runs once with
    # no retry (platform#1383), so a spot reclaim loses the whole run rather
    # than one task. CPU-only for now; GPU needs its own pool and instance
    # requirements. Karpenter provisions from zero, so an idle pool costs
    # nothing -- limits are the ceiling, not a reservation.
    ray-control = {
      engine        = "ray"
      role          = "control"
      capacity_type = "on-demand"
      limits        = { cpu = "100", memory = "400Gi" }
    }
    ray-worker = {
      engine        = "ray"
      role          = "worker"
      capacity_type = "on-demand"
      limits        = { cpu = "200", memory = "800Gi" }
    }
  }
  # Pools own hardware and capacity requirements; Spark pods select their role.
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
    for name, pool in local.karpenter_compute_pool_defaults :
    name => {
      enabled = true
      name    = name
      labels = merge({
        "zipline.ai/engine"   = pool.engine
        "zipline.ai/workload" = pool.engine
      }, pool.role == null ? {} : { "zipline.ai/role" = pool.role })
      taints = [{
        key      = "zipline.ai/workload"
        operator = "Equal"
        value    = pool.engine
        effect   = "NoSchedule"
      }]
      requirements = concat(
        [{
          key      = "karpenter.sh/capacity-type"
          operator = "In"
          values   = [pool.capacity_type]
        }],
        # Pinning explicit instance types REPLACES the category/generation selector
        # (Karpenter ANDs requirements, so keeping both would narrow to empty and
        # never provision); os/arch/capacity-type still apply.
        [for r in local.karpenter_compute_requirements :
        r if length(local.karpenter_compute_instance_types) == 0 || !contains(["karpenter.k8s.aws/instance-category", "karpenter.k8s.aws/instance-generation"], r.key)],
        length(local.karpenter_compute_instance_types) > 0 ? [{ key = "node.kubernetes.io/instance-type", operator = "In", values = local.karpenter_compute_instance_types }] : [],
        name == "spark-executor" ? [{ key = "karpenter.k8s.aws/instance-local-nvme", operator = "Exists" }] : [],
      )
      expireAfter = local.karpenter_compute_expire_after
      limits      = merge(pool.limits, local.karpenter_compute_limits, try(local.karpenter["${replace(name, "-", "_")}_limits"], {}))
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
      "zipline.ai/engine" = "spark"
      "zipline.ai/role"   = "driver"
    }
    tolerations = local.karpenter_compute_node_pools["spark-driver"].taints
  }
}

# Ray GPU execution profiles (platform contracts/training-v1 "Profile placement
# interface"). A profile is a named pair of Karpenter pools that a Ray training
# job opts into with `ray.placement.profile=<name>`:
#   - <name>          GPU workers: role=worker, pinned instance types
#   - <name>-control  CPU head/submitter: role=control, small c/m/r instances
# Both carry zipline.ai/engine=ray, zipline.ai/execution-profile=<name> and the
# zipline.ai/workload=ray-<name>:NoSchedule taint the Hub tolerates. Both scale
# from zero and reclaim empty nodes after a minute, so an idle profile costs
# nothing. The control pool is profile-owned rather than labels on a shared
# managed node group: a node group can carry only one execution-profile value,
# and any apply of that node group from a branch without the labels strands
# running heads.
#
# Configure under aws.karpenter.ray_gpu_profiles, e.g.
#   "ray_gpu_profiles": {
#     "s6e11-l40s": { "instance_types": ["g6e.xlarge", "g5.xlarge"], "max_gpus": 1 }
#   }
# Optional per profile: capacity_type ("on-demand"), expire_after ("48h"),
# worker_limits / control_limits (merged over the defaults below).
locals {
  ray_gpu_profiles = try(local.karpenter.ray_gpu_profiles, {})
  ray_gpu_profile_pools = {
    for name, profile in local.ray_gpu_profiles : name => {
      worker = {
        name = name
        labels = {
          "zipline.ai/engine"            = "ray"
          "zipline.ai/role"              = "worker"
          "zipline.ai/execution-profile" = name
        }
        taints = [{ key = "zipline.ai/workload", value = "ray-${name}", effect = "NoSchedule" }]
        requirements = [
          { key = "kubernetes.io/os", operator = "In", values = ["linux"] },
          { key = "kubernetes.io/arch", operator = "In", values = ["amd64"] },
          { key = "karpenter.sh/capacity-type", operator = "In", values = [try(profile.capacity_type, "on-demand")] },
          { key = "node.kubernetes.io/instance-type", operator = "In", values = tolist(profile.instance_types) },
        ]
        # The GPU limit is the hard ceiling on concurrent GPUs for this profile;
        # merged last so worker_limits cannot raise it.
        limits                 = merge(try(profile.worker_limits, {}), { "nvidia.com/gpu" = tostring(profile.max_gpus) })
        expireAfter            = try(profile.expire_after, "48h")
        terminationGracePeriod = "5m"
        disruption             = { consolidationPolicy = "WhenEmpty", consolidateAfter = "1m" }
      }
      control = {
        name = "${name}-control"
        labels = {
          "zipline.ai/engine"            = "ray"
          "zipline.ai/role"              = "control"
          "zipline.ai/execution-profile" = name
        }
        taints = [{ key = "zipline.ai/workload", value = "ray-${name}", effect = "NoSchedule" }]
        requirements = [
          { key = "kubernetes.io/os", operator = "In", values = ["linux"] },
          { key = "kubernetes.io/arch", operator = "In", values = ["amd64"] },
          { key = "karpenter.sh/capacity-type", operator = "In", values = ["on-demand"] },
          { key = "karpenter.k8s.aws/instance-category", operator = "In", values = ["c", "m", "r"] },
          { key = "karpenter.k8s.aws/instance-generation", operator = "Gt", values = ["5"] },
        ]
        limits                 = merge({ cpu = "32", memory = "128Gi" }, try(profile.control_limits, {}))
        expireAfter            = try(profile.expire_after, "48h")
        terminationGracePeriod = "5m"
        disruption             = { consolidationPolicy = "WhenEmpty", consolidateAfter = "1m" }
      }
    }
  }
  ray_gpu_profile_field_errors = flatten([
    for name, profile in local.ray_gpu_profiles : concat(
      can(regex("^[a-z0-9]([a-z0-9-]{0,40}[a-z0-9])?$", name)) ? [] : ["${name}: profile name must be a lowercase DNS label of at most 42 characters"],
      length(try(tolist(profile.instance_types), [])) > 0 ? [] : ["${name}: instance_types must be a non-empty list"],
      try(floor(profile.max_gpus) == profile.max_gpus && profile.max_gpus > 0, false) ? [] : ["${name}: max_gpus must be a positive integer"],
      contains(["on-demand", "spot"], try(profile.capacity_type, "on-demand")) ? [] : ["${name}: capacity_type must be on-demand or spot"],
      can(regex("^[0-9]+h$", try(profile.expire_after, "48h"))) ? [] : ["${name}: expire_after must be whole hours, e.g. 48h"],
    )
  ])
  # NodePools are cluster-scoped and each profile is a Helm release in the
  # Karpenter namespace: generated names must not collide with the shared pools,
  # the Karpenter releases, or another profile (e.g. "x" and "x-control").
  ray_gpu_pool_names = flatten([for name in keys(local.ray_gpu_profiles) : [name, "${name}-control"]])
  ray_gpu_reserved_names = concat(
    [for key, pool in local.karpenter_node_pool_inputs : try(pool.name, key)],
    [try(local.karpenter.release_name, "karpenter"), "${try(local.karpenter.release_name, "karpenter")}-nodepools"],
  )
  ray_gpu_profile_errors = concat(
    local.ray_gpu_profile_field_errors,
    [for name in distinct(local.ray_gpu_pool_names) : "${name}: name collides with a shared NodePool or Karpenter release" if contains(local.ray_gpu_reserved_names, name)],
    [for name in distinct(local.ray_gpu_pool_names) : "${name}: NodePool name is generated by more than one profile" if length([for other in local.ray_gpu_pool_names : other if other == name]) > 1],
  )
  # Namespace => max concurrent GPU requests. Optional cost/concurrency bound.
  ray_gpu_namespace_quotas = try(local.karpenter.ray_gpu_namespace_quotas, {})
}
