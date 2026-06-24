# Zipline Orchestration Module

Installs the shared `charts/zipline-orchestration` chart.

This module is intentionally cloud-neutral. Cloud-specific roots pass one shared
`orchestration` object for common install inputs, plus a cloud-specific Helm
values map through `values`.

The module owns common Kubernetes installation mechanics:

- Namespace creation.
- Shared Kubernetes addons.
- Optional Docker Hub pull secret creation.
- Common Helm values for global metadata, database, ingress, compute defaults,
  auth, and Prometheus.
- The `helm_release`.

Provider-specific controllers such as the AWS Secrets Store provider, AWS Load
Balancer Controller, and cloud identity bindings stay in cloud-specific
wrappers.

The cloud installation wrapper must pass `chart_path`; this module should not
assume the repository layout or which wrapper path is being applied.
