# Destroy-time cleanup for resources created in-cluster by controllers rather
# than by tofu: the ingress-nginx LoadBalancer Service (backed by a GKE L4 LB
# with a static external IP) and StarRocks CRs/StatefulSets. Without this
# cleanup, dangling LB forwarding rules and PD volumes keep the subnet/VPC
# pinned (VPC delete fails on in-use resources).
#
# Destroy runs in layers (reverse dependency order):
#   1. workload_drain               drains StarRocks before its helm uninstall
#   2. module.zipline_orchestration (hub chart, StarRocks)
#   3. controller_resource_cleanup  deletes leftover LB Services
#   4. node pools, cluster, network
#
# controller_resource_cleanup must not depend on the module: a hook only runs on
# destroy if it is in state, and anything that depends on the module is created
# after the hub chart. A failed hub-chart install would then leave the hook out
# of state and the next destroy unordered. Instead the module depends on the
# hook, so the hook is created as soon as the cluster and network exist.

resource "terraform_data" "controller_resource_cleanup" {
  triggers_replace = {
    cluster_name = local.cluster_name
    region       = local.cloud_args.region
    project      = local.cloud_args.project_id
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -o pipefail
      CN='${self.triggers_replace.cluster_name}'
      RG='${self.triggers_replace.region}'
      PR='${self.triggers_replace.project}'

      # Idempotent: on a repeat destroy the cluster may already be gone.
      if ! gcloud container clusters describe "$CN" --region "$RG" --project "$PR" >/dev/null 2>&1; then
        echo "cluster $CN not found; nothing to clean up"; exit 0
      fi

      KUBE="$(mktemp)"; trap 'rm -f "$KUBE"' EXIT
      if ! KUBECONFIG="$KUBE" gcloud container clusters get-credentials "$CN" --region "$RG" --project "$PR" >/dev/null 2>&1; then
        echo "could not fetch kubeconfig for $CN; skipping in-cluster cleanup"; exit 0
      fi
      export KUBECONFIG="$KUBE"

      echo "Deleting LoadBalancer Services so the controller removes their forwarding rules..."
      kubectl get svc -A -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null \
        | while read -r ns name; do
            [ -z "$ns" ] && continue
            echo "  deleting svc $ns/$name"
            kubectl delete svc "$name" -n "$ns" --ignore-not-found --wait=false || true
          done

      echo "Waiting up to 15m for LBs to go away..."
      for i in $(seq 1 90); do
        svc_left=$(kubectl get svc -A -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -c . || true)
        svc_left=$${svc_left:-0}
        echo "  attempt $i/90: loadbalancer services=$svc_left"
        if [ "$svc_left" -eq 0 ]; then
          echo "controller-managed resources cleaned up"; exit 0
        fi
        sleep 10
      done
      echo "WARNING: cleanup did not converge in 15m; VPC teardown may fail on lingering resources. Re-run 'tofu destroy'." >&2
      exit 0
    EOT
  }

  depends_on = [
    google_container_node_pool.pools,
    google_container_cluster.main,
    google_compute_subnetwork.main,
    google_compute_network.main,
  ]
}

# Runs before module.zipline_orchestration is destroyed. Only StarRocks needs
# draining ahead of its own helm uninstall. If this hook is missing from state
# (failed apply), the StarRocks uninstall may time out, but the destroy stops
# before the network, so a re-run is safe.
resource "terraform_data" "workload_drain" {
  triggers_replace = {
    cluster_name = local.cluster_name
    region       = local.cloud_args.region
    project      = local.cloud_args.project_id
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -o pipefail
      CN='${self.triggers_replace.cluster_name}'
      RG='${self.triggers_replace.region}'
      PR='${self.triggers_replace.project}'

      if ! gcloud container clusters describe "$CN" --region "$RG" --project "$PR" >/dev/null 2>&1; then
        echo "cluster $CN not found; nothing to drain"; exit 0
      fi

      KUBE="$(mktemp)"; trap 'rm -f "$KUBE"' EXIT
      if ! KUBECONFIG="$KUBE" gcloud container clusters get-credentials "$CN" --region "$RG" --project "$PR" >/dev/null 2>&1; then
        echo "could not fetch kubeconfig for $CN; skipping workload drain"; exit 0
      fi
      export KUBECONFIG="$KUBE"

      # §12.2: StarRocks FE/CN StatefulSets drain slower than helm_timeout, so
      # tofu's helm_release.starrocks uninstall times out and the CN pods'
      # PD volumes keep the subnet pinned. Delete the CRs + StatefulSets up
      # front so the operator scales CN down before helm uninstall runs.
      echo "Tearing down StarRocks (CRs + StatefulSets) so its nodes drain..."
      for sr in $(kubectl get crd -o name 2>/dev/null | grep -i starrocks | sed 's#.*/##'); do
        for ns in $(kubectl get "$sr" -A --no-headers 2>/dev/null | awk '{print $1}' | sort -u); do
          [ -z "$ns" ] && continue
          kubectl delete "$sr" --all -n "$ns" --ignore-not-found --wait=false 2>/dev/null || true
        done
      done
      kubectl get statefulset -A --no-headers 2>/dev/null | awk 'tolower($0) ~ /starrocks/ {print $1" "$2}' \
        | while read -r ns name; do
            [ -z "$ns" ] && continue
            kubectl delete statefulset "$name" -n "$ns" --ignore-not-found --wait=false 2>/dev/null || true
          done

      echo "Waiting up to 10m for StarRocks pods to terminate..."
      for i in $(seq 1 60); do
        left=$(kubectl get pods -A --no-headers 2>/dev/null | awk 'tolower($0) ~ /starrocks/' | grep -c . || true)
        left=$${left:-0}
        echo "  attempt $i/60: starrocks pods=$left"
        [ "$left" -eq 0 ] && exit 0
        sleep 10
      done
      echo "WARNING: StarRocks pods still present after 10m; its helm uninstall may time out." >&2
      exit 0
    EOT
  }

  depends_on = [module.zipline_orchestration]
}

# Final backup. AWS takes a final RDS snapshot on destroy; GCP has no
# equivalent lifecycle hook, so we trigger an on-demand backup via gcloud.
# Tolerant of already-deleted instance (set +e).
resource "terraform_data" "cloudsql_final_backup" {
  count = local.cloud_args.database_create_final_backup ? 1 : 0

  triggers_replace = {
    instance = google_sql_database_instance.zipline.name
    project  = local.cloud_args.project_id
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set +e
      gcloud sql backups create \
        --instance='${self.triggers_replace.instance}' \
        --project='${self.triggers_replace.project}' \
        --description="pre-destroy final backup $(date -u +%Y-%m-%dT%H:%M:%SZ)" || {
        echo "WARNING: final backup failed (instance may already be gone). Continuing destroy." >&2
      }
      exit 0
    EOT
  }

  depends_on = [google_sql_database_instance.zipline]
}
