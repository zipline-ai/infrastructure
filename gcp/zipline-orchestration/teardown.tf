# Destroy-time cleanup for resources created in-cluster by controllers rather
# than by tofu: the ingress-nginx LoadBalancer Service (backed by a GKE L4 LB
# with a static external IP), StarRocks CRs/StatefulSets, and PVCs attached to
# chart StatefulSets. Without this cleanup, dangling LB forwarding rules and PD
# volumes keep the subnet/VPC pinned (VPC delete fails on in-use resources).
#
# depends_on preserves the required destroy order:
#   1. drain StarRocks + delete LB Services (controllers still alive, cluster
#      still reachable)
#   2. optional final Cloud SQL on-demand backup
#   3. tofu destroys the module (helm uninstall), then node pools, then cluster
#   4. tofu destroys the network

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

      echo "Deleting LoadBalancer Services so the controller removes their forwarding rules..."
      kubectl get svc -A -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null \
        | while read -r ns name; do
            [ -z "$ns" ] && continue
            echo "  deleting svc $ns/$name"
            kubectl delete svc "$name" -n "$ns" --ignore-not-found --wait=false || true
          done

      echo "Waiting up to 15m for LBs and StarRocks pods to go away..."
      for i in $(seq 1 90); do
        svc_left=$(kubectl get svc -A -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -c . || true)
        sr_pods=$(kubectl get pods -A --no-headers 2>/dev/null | awk 'tolower($0) ~ /starrocks/' | grep -c . || true)
        svc_left=$${svc_left:-0}; sr_pods=$${sr_pods:-0}
        echo "  attempt $i/90: loadbalancer services=$svc_left, starrocks pods=$sr_pods"
        if [ "$svc_left" -eq 0 ] && [ "$sr_pods" -eq 0 ]; then
          echo "controller-managed resources cleaned up"; exit 0
        fi
        sleep 10
      done
      echo "WARNING: cleanup did not converge in 15m; VPC teardown may fail on lingering resources. Re-run 'tofu destroy'." >&2
      exit 0
    EOT
  }

  depends_on = [
    module.zipline_orchestration,
    google_container_node_pool.pools,
    google_container_cluster.main,
    google_compute_subnetwork.main,
    google_compute_network.main,
  ]
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
