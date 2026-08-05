# Destroy-time cleanup for AWS resources created by in-cluster controllers rather
# than by tofu: the ingress-nginx LoadBalancer Service (which the aws-load-balancer
# controller backs with an NLB) and Karpenter-provisioned EC2 nodes. Neither is in
# tofu state, so a plain `tofu destroy` leaves them running; their ENIs then keep
# public IPs mapped in the VPC and block internet-gateway detach and subnet/VPC
# deletion (DependencyViolation), while their buckets stay populated.
#
# depends_on lists the controllers this cleanup relies on, so tofu destroys this
# resource FIRST (reverse-dependency order) while Karpenter and the LB controller
# are still running to process the deletions. The provisioner deletes the
# LoadBalancer Services and Karpenter NodeClaims/NodePools, then blocks until the
# NLBs and nodes are actually gone before tofu proceeds to tear down the VPC.
#
# Karpenter and the LB controller run on the managed node group (not on
# Karpenter nodes), so draining Karpenter nodes here does not kill the controllers.
resource "terraform_data" "controller_resource_cleanup" {
  triggers_replace = {
    cluster_name = local.cluster_name
    region       = local.cloud_args.region
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -o pipefail
      CN='${self.triggers_replace.cluster_name}'
      RG='${self.triggers_replace.region}'

      # Idempotent: on a repeat destroy the cluster may already be gone.
      if ! aws eks describe-cluster --name "$CN" --region "$RG" >/dev/null 2>&1; then
        echo "cluster $CN not found; nothing to clean up"; exit 0
      fi

      KUBE="$(mktemp)"; trap 'rm -f "$KUBE"' EXIT
      if ! aws eks update-kubeconfig --name "$CN" --region "$RG" --kubeconfig "$KUBE" >/dev/null 2>&1; then
        echo "could not fetch kubeconfig for $CN; skipping in-cluster cleanup"; exit 0
      fi
      export KUBECONFIG="$KUBE"

      echo "Stopping Karpenter provisioning and draining its nodes..."
      kubectl delete nodepools.karpenter.sh --all --ignore-not-found --wait=false || true
      # Karpenter refuses to evict pods annotated karpenter.sh/do-not-disrupt during
      # node termination — the warm-pool deployment sets it to pin nodes warm, and
      # spark drivers set it too — so the node never drains and the NodeClaim /
      # EC2NodeClass deletes below hang forever. Strip the annotation from every pod
      # so the nodes can drain. NodePools are already deleted above, so any pod the
      # owning controller reschedules just goes Pending and blocks nothing.
      kubectl annotate pods --all-namespaces --all karpenter.sh/do-not-disrupt- >/dev/null 2>&1 || true
      kubectl delete nodeclaims.karpenter.sh --all --ignore-not-found --wait=false || true
      # Delete the EC2NodeClass here too. Its karpenter.k8s.aws/termination finalizer
      # is cleared by Karpenter's nodeclass controller, which needs IAM/EC2 egress.
      # If left for the karpenter-nodepools helm uninstall (which runs AFTER this
      # cleanup, once egress may already be gone), the finalizer never clears, the
      # uninstall hangs, and the whole karpenter -> nodegroup -> IGW chain deadlocks.
      # Clearing it here — while egress is still up (depends_on) — drains all
      # Karpenter CRs so nothing is left needing AWS APIs after egress tears down.
      kubectl delete ec2nodeclasses.karpenter.k8s.aws --all --ignore-not-found --wait=false || true

      # Drop the EKS-default coredns PDB (maxUnavailable=1). During the managed
      # nodegroup delete that follows, coredns can't be evicted once it has nowhere
      # left to reschedule (disruptionsAllowed=0), so EKS waits on its drain grace
      # timeout before force-terminating the last node — minutes of dead time on
      # every teardown. Removing the PDB here (teardown-only) lets the last node
      # drain promptly.
      kubectl delete pdb coredns -n kube-system --ignore-not-found || true

      # StarRocks: the operator's FE/CN StatefulSets drain slower than helm_timeout,
      # so tofu's helm_release.starrocks uninstall times out ("context deadline
      # exceeded") and the CN nodes' ENIs keep the internet gateway pinned
      # (DependencyViolation). Delete the StarRocks custom resources + StatefulSets
      # up front so the operator scales the CN cluster down, the nodes drain, and the
      # later helm uninstall is a no-op. The CRD name varies by operator version, so
      # discover it rather than hardcode.
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

      echo "Deleting LoadBalancer Services so the LB controller removes their NLBs..."
      kubectl get svc -A -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null \
        | while read -r ns name; do
            [ -z "$ns" ] && continue
            echo "  deleting svc $ns/$name"
            kubectl delete svc "$name" -n "$ns" --ignore-not-found --wait=false || true
          done

      echo "Waiting up to 15m for NLBs, Karpenter nodes, and EC2NodeClasses to be removed..."
      for i in $(seq 1 90); do
        svc_left=$(kubectl get svc -A -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -c . || true)
        nc_left=$(kubectl get nodeclaims.karpenter.sh -o name 2>/dev/null | grep -c . || true)
        ec2nc_left=$(kubectl get ec2nodeclasses.karpenter.k8s.aws -o name 2>/dev/null | grep -c . || true)
        svc_left=$${svc_left:-0}; nc_left=$${nc_left:-0}; ec2nc_left=$${ec2nc_left:-0}
        echo "  attempt $i/90: loadbalancer services=$svc_left, karpenter nodeclaims=$nc_left, ec2nodeclasses=$ec2nc_left"
        if [ "$svc_left" -eq 0 ] && [ "$nc_left" -eq 0 ] && [ "$ec2nc_left" -eq 0 ]; then
          echo "controller-managed resources cleaned up"; exit 0
        fi
        sleep 10
      done
      echo "WARNING: cleanup did not converge in 15m; VPC teardown may fail on lingering ENIs. Re-run 'tofu destroy'." >&2
      exit 0
    EOT
  }

  # Ordering is load-bearing. On destroy this resource runs its provisioner FIRST
  # (before everything it depends on is torn down), so the controllers must still
  # be running AND still have network egress to the AWS APIs:
  #   - karpenter / lb-controller / chart: alive to process the deletions.
  #   - VPC networking (route table association, route table, subnets, IGW, VPC):
  #     egress to EC2/ELB. When the network is tofu-managed (create_network), the
  #     subnet->public-route-table association (which routes 0.0.0.0/0 to the IGW)
  #     is NOT in the EKS cluster's dependency chain, so without these edges tofu
  #     removes it concurrently, the subnets fall back to the main route table,
  #     and Karpenter/the LB controller lose egress mid-drain (EC2
  #     DescribeInstances i/o timeout) and can never terminate the nodes or delete
  #     the NLB. Referencing count=0 network resources (customer-supplied VPC) is
  #     a harmless empty set.
  depends_on = [
    helm_release.karpenter,
    helm_release.karpenter_nodepools,
    helm_release.aws_load_balancer_controller,
    module.zipline_orchestration,
    aws_route_table_association.public,
    aws_route_table.public,
    aws_subnet.zipline,
    aws_internet_gateway.gw,
    aws_vpc.main,
  ]
}
