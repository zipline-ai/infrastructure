locals {
  cluster_name = local.cloud_args.cluster_name != "" ? local.cloud_args.cluster_name : "${local.name_prefix}-gke"

  # Parity with AWS node-pools.tf: zipline.ai/node-pool=system taint on system,
  # zipline.ai/workload=<engine> on compute pools. Keys come from
  # CrucibleLabels.scala:13-16 — the chart's nodeSelectors (incl.
  # compute.warmPool) and the image-prepull DaemonSet resolve against these.
  system_node_pool            = "system"
  system_node_selector        = { "zipline.ai/node-pool" = local.system_node_pool }
  system_node_tolerations     = [{ key = "zipline.ai/node-pool", operator = "Equal", value = local.system_node_pool, effect = "NoSchedule" }]
  image_prepull_node_selector = { "zipline.ai/engine" = "spark", "zipline.ai/role" = "executor" }
  # image-prepull lands on executor (arm64) nodes — tolerate GKE's auto arch taint.
  image_prepull_node_tolerations = [
    { key = "zipline.ai/workload", operator = "Equal", value = "spark", effect = "NoSchedule" },
    { key = "kubernetes.io/arch", operator = "Exists", effect = "NoSchedule" },
  ]

  node_pools_defaults = {
    system = {
      machine_type  = local.cloud_args.system_machine_type
      capacity_type = "on-demand"
      disk_size_gb  = 100
      min_count     = 1
      max_count     = 3
      initial_count = 1
      labels        = { "zipline.ai/team" = "system", "zipline.ai/node-pool" = local.system_node_pool }
      # No taints on the system pool: GKE-managed system pods (kube-dns,
      # metrics-server, kube-state-metrics, l7-default-backend) don't tolerate
      # custom taints, so a system-pool taint strands the entire cluster
      # control plane. AWS gets away with the equivalent taint because EKS
      # runs those pods on the managed control plane; GKE runs them on your
      # nodes. The label alone + the chart's nodeSelector is enough to steer
      # workloads to this pool.
      taints    = []
      local_ssd = false
    }
    spark-driver = {
      machine_type  = local.cloud_args.compute_machine_type
      capacity_type = "on-demand"
      disk_size_gb  = 100
      min_count     = 1
      max_count     = 10
      initial_count = 1
      labels        = { "zipline.ai/engine" = "spark", "zipline.ai/workload" = "spark", "zipline.ai/role" = "driver" }
      taints        = [{ key = "zipline.ai/workload", operator = "Equal", value = "spark", effect = "NoSchedule" }]
      local_ssd     = false
    }
    spark-executor = {
      machine_type  = local.cloud_args.executor_machine_type
      capacity_type = "spot"
      disk_size_gb  = 100
      min_count     = 0
      max_count     = 14
      initial_count = 0
      labels        = { "zipline.ai/engine" = "spark", "zipline.ai/workload" = "spark", "zipline.ai/role" = "executor" }
      taints        = [{ key = "zipline.ai/workload", operator = "Equal", value = "spark", effect = "NoSchedule" }]
      # Local SSD is part of the machine shape (-lssd suffix) rather than a
      # separate ephemeral_storage_local_ssd_config block, so leave this false.
      local_ssd = false
    }
    flink = {
      machine_type  = local.cloud_args.compute_machine_type
      capacity_type = "on-demand"
      disk_size_gb  = 100
      min_count     = 0
      max_count     = 16
      initial_count = 0
      labels        = { "zipline.ai/engine" = "flink", "zipline.ai/workload" = "flink" }
      taints        = [{ key = "zipline.ai/workload", operator = "Equal", value = "flink", effect = "NoSchedule" }]
      local_ssd     = false
    }
    ray-control = {
      machine_type  = local.cloud_args.compute_machine_type
      capacity_type = "on-demand"
      disk_size_gb  = 100
      min_count     = 0
      max_count     = 4
      initial_count = 0
      labels        = { "zipline.ai/engine" = "ray", "zipline.ai/workload" = "ray", "zipline.ai/role" = "control" }
      taints        = [{ key = "zipline.ai/workload", operator = "Equal", value = "ray", effect = "NoSchedule" }]
      local_ssd     = false
    }
    ray-worker = {
      machine_type  = local.cloud_args.compute_machine_type
      capacity_type = "on-demand"
      disk_size_gb  = 100
      min_count     = 0
      max_count     = 8
      initial_count = 0
      labels        = { "zipline.ai/engine" = "ray", "zipline.ai/workload" = "ray", "zipline.ai/role" = "worker" }
      taints        = [{ key = "zipline.ai/workload", operator = "Equal", value = "ray", effect = "NoSchedule" }]
      local_ssd     = false
    }
  }
  node_pools = merge(local.node_pools_defaults, try(local.cloud_args.node_pools, {}))

  # Pre-warm on-demand Spark driver capacity (chart compute.warmPool).
  # GKE auto-taints c4a/arm64 nodes with kubernetes.io/arch=arm64:NoSchedule.
  # Crucible's own Spark/Flink/Ray submitters already emit a matching
  # archToleration (CrucibleKubernetesSpecs.scala:701), but the chart's
  # warm-pool deployment doesn't — add it here so pause pods schedule on
  # the Arm compute pool.
  compute_warm_pool = {
    enabled      = true
    nodeSelector = { "zipline.ai/engine" = "spark", "zipline.ai/role" = "driver" }
    tolerations = [
      { key = "zipline.ai/workload", operator = "Equal", value = "spark", effect = "NoSchedule" },
      { key = "kubernetes.io/arch", operator = "Exists", effect = "NoSchedule" },
    ]
  }
}

# Service account used by node VMs. Separate from workload identity (which runs
# per-pod). This is the OAuth identity the node itself exposes to GKE/kubelet.
resource "google_service_account" "nodes" {
  account_id   = "${local.name_prefix}-gke-nodes"
  display_name = "${local.name_prefix} GKE node pool service account"
}

# Minimum required roles for GKE node VMs: logging/metrics writer, autoscaler
# metrics, Artifact Registry read, and Monitoring Metric Writer. Mirrors
# GKE's default node-sa recommendations.
resource "google_project_iam_member" "nodes" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/artifactregistry.reader",
  ])

  project = local.cloud_args.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_container_cluster" "main" {
  provider = google-beta

  name     = local.cluster_name
  location = local.cloud_args.region

  # The parity-with-EKS posture (§4): public endpoint + public nodes + no NAT.
  # Access gated by Google IAM and k8s RBAC. Variables exist to tighten later
  # without code changes.
  private_cluster_config {
    enable_private_nodes    = local.cloud_args.enable_private_nodes
    enable_private_endpoint = local.cloud_args.enable_private_endpoint
    master_ipv4_cidr_block  = local.cloud_args.enable_private_nodes || local.cloud_args.enable_private_endpoint ? local.cloud_args.master_ipv4_cidr_block : null
  }

  # Only emit master_authorized_networks when authorized_networks is non-empty.
  # Omitting the block entirely = allow all (EKS parity: no public_access_cidrs).
  dynamic "master_authorized_networks_config" {
    for_each = length(local.cloud_args.authorized_networks) > 0 ? [1] : []
    content {
      dynamic "cidr_blocks" {
        for_each = local.cloud_args.authorized_networks
        content {
          cidr_block   = cidr_blocks.value.cidr_block
          display_name = try(cidr_blocks.value.display_name, cidr_blocks.value.cidr_block)
        }
      }
    }
  }

  # The cluster is created with the default pool detached — we manage pools
  # ourselves (google_container_node_pool below). GKE still requires the
  # initial_node_count/node_config block.
  remove_default_node_pool = true
  initial_node_count       = 1

  deletion_protection = local.cloud_args.gke_deletion_protection

  network    = local.network_self_link
  subnetwork = local.subnet_self_link

  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  workload_identity_config {
    workload_pool = "${local.cloud_args.project_id}.svc.id.goog"
  }

  release_channel {
    channel = upper(local.cloud_args.gke_release_channel)
  }

  # Weekend maintenance window. The window is in RFC3339 UTC; us-central1 is
  # UTC-6 (CST) or UTC-5 (CDT). Use 08:00 UTC Saturday to match 02:00 local.
  maintenance_policy {
    recurring_window {
      start_time = "2026-01-03T08:00:00Z"
      end_time   = "2026-01-03T12:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SA"
    }
  }

  logging_config {
    enable_components = local.cloud_args.logging_components
  }

  monitoring_config {
    enable_components = local.cloud_args.monitoring_components

    managed_prometheus {
      enabled = true
    }
  }

  cluster_autoscaling {
    autoscaling_profile = local.cloud_args.autoscaling_profile
    # We define pool-level autoscaling (min/max per pool) in
    # google_container_node_pool. Leave Node Auto-Provisioning disabled.
    enabled = false
  }

  # Default node_config: nodes created by the auto-removed default pool.
  # The explicit pools below use their own node_config.
  node_config {
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  lifecycle {
    ignore_changes = [
      # The default pool is removed, but Terraform otherwise keeps diffing
      # the initial node config. Harmless.
      node_config,
      initial_node_count,
    ]
  }

  depends_on = [
    google_project_iam_member.nodes,
  ]
}

resource "google_container_node_pool" "pools" {
  provider = google-beta
  for_each = local.node_pools

  name     = each.key
  cluster  = google_container_cluster.main.name
  location = local.cloud_args.region

  initial_node_count = each.value.initial_count

  autoscaling {
    min_node_count = each.value.min_count
    max_node_count = each.value.max_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  # c4a pools occasionally return status=ERROR from GKE's create call even
  # when the pool's own reconciler heals it to RUNNING within seconds. Default
  # Terraform timeouts (~10m) are long enough for the heal, but it only helps
  # if the provider actually polls past the first status read — bump explicitly
  # to be unambiguous.
  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }

  node_config {
    machine_type = each.value.machine_type
    disk_size_gb = each.value.disk_size_gb
    # c4a (Arm Axion) machines only support hyperdisk-balanced boot disks —
    # pd-balanced and pd-ssd both fail at instance create with
    # UNSUPPORTED_OPERATION. x86 pools stay on pd-balanced (cheaper, same
    # performance at these sizes). Per-pool `disk_type` in cloud_args.node_pools
    # overrides either default.
    disk_type = try(
      each.value.disk_type,
      startswith(each.value.machine_type, "c4a-") || startswith(each.value.machine_type, "t2a-") ? "hyperdisk-balanced" : "pd-balanced",
    )

    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    spot = each.value.capacity_type == "spot"

    labels = each.value.labels

    dynamic "taint" {
      for_each = each.value.taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = "NO_SCHEDULE"
      }
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    # c4a-standard-8-lssd machines come with 2 local SSDs attached. GKE
    # auto-provisions them with the pool, but if TF doesn't declare the block
    # it reads back and wants to remove them — a ForceNew field, so this
    # would trigger a pool replace on every refresh. Spark shuffle scratch
    # uses these; keep them.
    dynamic "ephemeral_storage_local_ssd_config" {
      for_each = endswith(each.value.machine_type, "-lssd") ? [1] : []
      content {
        local_ssd_count = 2
      }
    }
  }

  lifecycle {
    ignore_changes = [
      # initial_node_count is only used at pool create; the autoscaler governs
      # the running count afterwards.
      initial_node_count,
    ]
  }
}
