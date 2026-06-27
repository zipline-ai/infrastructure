# Zipline Kubernetes Add-ons

Installs shared cluster add-ons used by the Zipline Kubernetes deployment.

Cloud-specific controllers and identity bindings should stay in cloud wrappers.
For example, AWS installs the AWS Secrets Store CSI provider and AWS Load
Balancer Controller next to this module, while Azure can rely on AKS add-ons or
install provider-specific components in its wrapper.
