#!/usr/bin/env bash
# Read-only preflight. Default mode uses the scoped submitter role. --admin adds
# cluster inventory and must run separately with infrastructure-reader credentials.
set -euo pipefail
mode=submitter
case "${1:-}" in
  "") ;;
  --admin) mode=admin ;;
  *) echo "Usage: $0 [--admin]" >&2; exit 2 ;;
esac
region="${AWS_REGION:-us-west-2}"
cluster="${EKS_CLUSTER_NAME:-public-demo-eks}"
account="${EXPECTED_AWS_ACCOUNT:-345594603419}"
namespace=zipline-s6e11-dev
actual=$(aws sts get-caller-identity --query Account --output text)
[[ "$actual" == "$account" ]] || { echo "Wrong AWS account" >&2; exit 1; }
kube=$(mktemp); trap 'rm -f "$kube"' EXIT
aws eks update-kubeconfig --name "$cluster" --region "$region" --kubeconfig "$kube" >/dev/null
export KUBECONFIG="$kube"
aws eks describe-cluster --name "$cluster" --region "$region" --query 'cluster.{arn:arn,version:version,subnets:resourcesVpcConfig.subnetIds}'
kubectl get namespace "$namespace"
kubectl get resourcequota,limitrange,serviceaccount -n "$namespace"
kubectl get rayjobs.ray.io -n "$namespace"
if [[ "$mode" == submitter ]]; then
  kubectl auth can-i create rayjobs.ray.io -n "$namespace"
  kubectl auth can-i delete rayjobs.ray.io -n "$namespace"
  # Fail when accidentally using admin or an overprivileged role.
  for action in "create pods" "get secrets" "create rayjobs.ray.io"; do
    read -r verb resource <<< "$action"
    if kubectl auth can-i "$verb" "$resource" -n zipline-default --quiet; then
      echo "Unexpected production permission: $action; use the scoped submitter role" >&2; exit 1
    fi
  done
  echo "Submitter preflight passed; run --admin separately for node/operator inventory."
  exit 0
fi
kubectl get nodes -o custom-columns='NAME:.metadata.name,ARCH:.status.nodeInfo.architecture,GPU:.status.allocatable.nvidia\.com/gpu'
kubectl get ds -A -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,IMAGE:.spec.template.spec.containers[*].image'
kubectl get deploy -A -l app.kubernetes.io/name=kuberay-operator
kubectl explain rayjob.spec.activeDeadlineSeconds
kubectl explain rayjob.spec.preRunningDeadlineSeconds
kubectl get nodepools -o custom-columns='NAME:.metadata.name,CPU:.spec.limits.cpu,MEMORY:.spec.limits.memory,GPU:.spec.limits.nvidia\.com/gpu'
