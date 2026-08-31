# Zipline Kubernetes Add-ons

Installs shared cluster add-ons used by the Zipline Kubernetes deployment.

Cloud-specific controllers and identity bindings should stay in cloud wrappers.
For example, AWS installs the AWS Load Balancer Controller next to this module,
while this module owns shared controllers such as External Secrets Operator and
cert-manager. It also installs the KubeRay operator and its custom resource
definitions by default, but does not create Ray workloads or install the KubeRay
API server.

Set `kuberay_operator_skip_crds` to `true` when another system manages the
KubeRay custom resource definitions. This prevents Helm from installing them; it
does not remove custom resource definitions that are already installed.
