#!/usr/bin/env bash
# Read-only preflight. Writes only an isolated temporary kubeconfig.
set -euo pipefail
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
kubectl auth can-i create rayjobs.ray.io -n "$namespace"
kubectl auth can-i delete rayjobs.ray.io -n "$namespace"
# Must be "no" for the submitter role (administrators naturally differ).
kubectl auth can-i create pods -n zipline-default || true
kubectl get rayjobs.ray.io -n "$namespace"
# Following inventory needs an infrastructure reader/admin, not the submitter role.
kubectl get nodes -o custom-columns='NAME:.metadata.name,ARCH:.status.nodeInfo.architecture,GPU:.status.allocatable.nvidia\.com/gpu'
kubectl get ds -A -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,IMAGE:.spec.template.spec.containers[*].image'
kubectl get deploy -A -l app.kubernetes.io/name=kuberay-operator
kubectl explain rayjob.spec.activeDeadlineSeconds
kubectl explain rayjob.spec.preRunningDeadlineSeconds
kubectl get nodepools -o custom-columns='NAME:.metadata.name,CPU:.spec.limits.cpu,MEMORY:.spec.limits.memory,GPU:.spec.limits.nvidia\.com/gpu'
