resource "google_container_cluster" "main" {
  project  = local.project_id
  name     = local.cluster_name
  location = local.region

  network    = local.network_self_link
  subnetwork = local.subnetwork_self_link

  remove_default_node_pool = true
  initial_node_count       = 1
  min_master_version       = local.cloud_args.kubernetes_version
  deletion_protection      = local.cloud_args.deletion_protection

  release_channel {
    channel = local.cloud_args.release_channel
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = local.cloud_args.pods_range_name
    services_secondary_range_name = local.cloud_args.services_range_name
  }

  private_cluster_config {
    enable_private_nodes    = local.cloud_args.private_nodes
    enable_private_endpoint = local.cloud_args.enable_private_endpoint
    master_ipv4_cidr_block  = local.cloud_args.private_nodes ? local.cloud_args.master_ipv4_cidr_block : null
  }

  dynamic "master_authorized_networks_config" {
    for_each = length(local.cloud_args.master_authorized_networks) == 0 ? [] : [true]
    content {
      dynamic "cidr_blocks" {
        for_each = local.cloud_args.master_authorized_networks
        content {
          cidr_block   = cidr_blocks.value.cidr_block
          display_name = try(cidr_blocks.value.display_name, null)
        }
      }
    }
  }

  workload_identity_config {
    workload_pool = "${local.project_id}.svc.id.goog"
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]

    managed_prometheus {
      enabled = true
    }
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  addons_config {
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
  }

  depends_on = [google_project_service.required]
}

resource "google_container_node_pool" "system" {
  project  = local.project_id
  name     = local.system_node_pool.name
  location = local.region
  cluster  = google_container_cluster.main.name

  version            = local.cloud_args.kubernetes_version
  initial_node_count = local.system_node_pool.initial_node_count

  autoscaling {
    total_min_node_count = local.system_node_pool.min_node_count
    total_max_node_count = local.system_node_pool.max_node_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    service_account = google_service_account.gke_nodes.email
    machine_type    = local.system_node_pool.machine_type
    disk_type       = local.system_node_pool.disk_type
    disk_size_gb    = local.system_node_pool.disk_size_gb
    image_type      = local.system_node_pool.image_type
    spot            = local.system_node_pool.spot
    labels          = local.system_node_pool.labels

    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    dynamic "taint" {
      for_each = local.system_node_pool.taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }
  }

  lifecycle {
    ignore_changes = [initial_node_count]
  }
}

resource "google_container_node_pool" "additional" {
  for_each = local.cloud_args.node_pools

  project  = local.project_id
  name     = each.key
  location = local.region
  cluster  = google_container_cluster.main.name

  version            = local.cloud_args.kubernetes_version
  initial_node_count = try(each.value.initial_node_count, 1)

  autoscaling {
    total_min_node_count = try(each.value.min_node_count, 0)
    total_max_node_count = try(each.value.max_node_count, 3)
  }

  management {
    auto_repair  = try(each.value.auto_repair, true)
    auto_upgrade = try(each.value.auto_upgrade, true)
  }

  node_config {
    service_account = google_service_account.gke_nodes.email
    machine_type    = try(each.value.machine_type, "e2-standard-8")
    disk_type       = try(each.value.disk_type, "pd-balanced")
    disk_size_gb    = try(each.value.disk_size_gb, 128)
    image_type      = try(each.value.image_type, "COS_CONTAINERD")
    spot            = try(each.value.spot, false)
    labels          = try(each.value.labels, {})

    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    dynamic "taint" {
      for_each = try(each.value.taints, [])
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }
  }

  lifecycle {
    ignore_changes = [initial_node_count]
  }
}
