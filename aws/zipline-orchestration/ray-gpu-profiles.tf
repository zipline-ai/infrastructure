# Ray GPU execution profiles: Karpenter pools, NVIDIA device plugin and optional
# namespace GPU quotas. Pool shapes and validation live in node-pools.tf
# (local.ray_gpu_profile_pools). Nothing here is created unless
# aws.karpenter.ray_gpu_profiles is non-empty.

# One release per profile, separate from the shared nodepools release, so
# adding/removing a profile never re-renders the EC2NodeClass or CPU pools.
resource "helm_release" "ray_gpu_profile" {
  for_each = local.karpenter.enabled ? local.ray_gpu_profiles : {}

  name      = each.key
  chart     = "${path.module}/charts/karpenter-nodepools"
  namespace = local.karpenter.namespace
  values = [yamlencode({
    # No ec2NodeClass key: reference the shared class without rendering it again.
    nodePools = {
      worker  = merge(local.ray_gpu_profile_pools[each.key].worker, { nodeClassRef = { name = local.karpenter_ec2_node_class.name } })
      control = merge(local.ray_gpu_profile_pools[each.key].control, { nodeClassRef = { name = local.karpenter_ec2_node_class.name } })
    }
  })]

  lifecycle {
    precondition {
      condition     = length(local.ray_gpu_profile_errors) == 0
      error_message = "Invalid aws.karpenter.ray_gpu_profiles: ${join("; ", local.ray_gpu_profile_errors)}"
    }
  }

  depends_on = [helm_release.karpenter_nodepools]
}

# NVIDIA's static device plugin advertises nvidia.com/gpu on any Karpenter
# NVIDIA node. The AL2023 NVIDIA AMI (selected automatically by the shared
# EC2NodeClass for GPU instance types) supplies the driver, container toolkit
# and default nvidia runtime; verified with g5.xlarge (A10G, driver 580).
resource "kubernetes_daemon_set_v1" "nvidia_device_plugin" {
  count = local.karpenter.enabled && length(local.ray_gpu_profiles) > 0 ? 1 : 0

  metadata {
    name      = "nvidia-device-plugin"
    namespace = "kube-system"
  }
  spec {
    selector { match_labels = { app = "nvidia-device-plugin" } }
    template {
      metadata { labels = { app = "nvidia-device-plugin" } }
      spec {
        priority_class_name = "system-node-critical"
        node_selector = {
          "karpenter.k8s.aws/instance-gpu-manufacturer" = "nvidia"
        }
        # GPU pools are tainted per profile; the plugin must run on all of them.
        toleration {
          operator = "Exists"
          effect   = "NoSchedule"
        }
        container {
          name  = "nvidia-device-plugin"
          image = "nvcr.io/nvidia/k8s-device-plugin:v0.17.1"
          env {
            name  = "FAIL_ON_INIT_ERROR"
            value = "true"
          }
          security_context {
            allow_privilege_escalation = false
            capabilities { drop = ["ALL"] }
          }
          resources {
            requests = { cpu = "50m", memory = "64Mi" }
            limits   = { memory = "256Mi" }
          }
          volume_mount {
            name       = "device-plugin"
            mount_path = "/var/lib/kubelet/device-plugins"
          }
        }
        volume {
          name = "device-plugin"
          host_path { path = "/var/lib/kubelet/device-plugins" }
        }
      }
    }
  }
}

resource "kubernetes_resource_quota_v1" "ray_gpu" {
  for_each = local.ray_gpu_namespace_quotas

  metadata {
    name      = "zipline-gpu"
    namespace = each.key
  }
  spec { hard = { "requests.nvidia.com/gpu" = tostring(each.value) } }

  # The orchestration release renders the compute namespaces.
  depends_on = [module.zipline_orchestration]
}

# Adopt the resources created by the earlier Crucible-only s6e11 branch so the
# first apply updates them in place instead of destroying a live GPU pool.
moved {
  from = helm_release.s6e11_l40s[0]
  to   = helm_release.ray_gpu_profile["s6e11-l40s"]
}

moved {
  from = kubernetes_daemon_set_v1.s6e11_nvidia_device_plugin[0]
  to   = kubernetes_daemon_set_v1.nvidia_device_plugin[0]
}

moved {
  from = kubernetes_resource_quota_v1.s6e11_gpu[0]
  to   = kubernetes_resource_quota_v1.ray_gpu["zipline-default"]
}
