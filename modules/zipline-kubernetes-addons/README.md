# Zipline Kubernetes Add-ons

Installs shared cluster add-ons used by the Zipline Kubernetes deployment.

Cloud-specific controllers and identity bindings should stay in cloud wrappers.
For example, AWS installs the AWS Load Balancer Controller next to this module,
while this module owns shared controllers such as External Secrets Operator and
cert-manager.
