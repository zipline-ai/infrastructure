# Zipline Orchestration Helm Module

Installs the shared `charts/zipline-orchestration` chart.

This module is intentionally cloud-neutral. Cloud-specific roots should build a
normal Helm values map from provider resources and pass it through `values`,
`extra_values`, or `extra_values_yaml`.

The module owns only the release namespace and `helm_release`. Provider-specific
controllers such as CSI providers, load balancer controllers, and identity
bindings belong in cloud-specific wrappers or shared add-on modules.

The cloud installation wrapper must pass `chart_path`; this module should not
assume the repository layout or which wrapper path is being applied.
