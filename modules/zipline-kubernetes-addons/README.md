# Zipline Kubernetes Add-ons

Installs shared cluster add-ons used by the Zipline Kubernetes deployment.
Zipline-managed operators run in the existing namespace supplied through
`namespace` (`zipline-system` by default in the orchestration module). Metrics
Server remains in `kube-system`.

Cloud-specific controllers and identity bindings should stay in cloud wrappers.
For example, AWS installs the AWS Load Balancer Controller next to this module,
while this module owns shared controllers such as External Secrets Operator and
cert-manager. It also installs the KubeRay operator and its custom resource
definitions by default, but does not create Ray workloads or install the KubeRay
API server.

Existing installations that used dedicated operator namespaces must follow
[the operator namespace migration](MIGRATION.md) before applying the namespace
change. Changing a Helm release namespace directly makes Terraform replace the
release and can delete chart-managed custom resource definitions.

Set `kuberay_operator_skip_crds` to `true` when another system manages the
KubeRay custom resource definitions. This prevents Helm from installing them; it
does not remove custom resource definitions that are already installed.
