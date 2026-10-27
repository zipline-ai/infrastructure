# Zipline Orchestration Module

Installs the shared `charts/zipline-orchestration` chart.

This module is intentionally cloud-neutral. Cloud-specific roots pass one shared
`orchestration` object for common install inputs and a `provider_context` object
for cloud-specific values such as identity annotations, runtime environment,
object store settings, and Helm provider values. This module owns the merge
between those two inputs before rendering chart values.

Hub metrics default to Chronon's Prometheus reader on port `8905` in this shared
module/chart layer, so AWS and Azure wrappers inherit the same behavior. Set
`orchestration.hub.chronon_metrics_reader` or `orchestration.hub.metrics_port`
to override it.

The shared chart fixes Crucible compute to Spark 4 for every provider. The
module ignores legacy Spark, Flink, and History Server image fields, always
prepulls the Spark 4 image when prepulling is enabled, and derives Spark 4 Hub
and Eval tags from `orchestration.deployment.zipline_version`.

The module owns common Kubernetes installation mechanics:

- Namespace creation.
- Shared Kubernetes addons.
- Optional Docker Hub pull secret creation.
- Common Helm values for global metadata, database, ingress, compute defaults,
  auth, and Prometheus.
- The `helm_release`.
- Provider-neutral public ingress outputs, including
  `ingress_load_balancer_target`, for environment-specific DNS automation.

Provider-specific controllers such as the AWS Load Balancer Controller and cloud
identity bindings stay in cloud-specific wrappers. Shared controllers such as
External Secrets Operator are installed through the add-ons module.

## Data Explorer

Data Explorer is disabled by default. Add this field to the existing
`orchestration` object in each environment's tfvars to enable it:

```hcl
orchestration = {
  # Existing deployment and other settings...
  data_explorer = {
    enabled = true
  }
}
```

Set `enabled = false` or omit `data_explorer` to disable the UI feature,
StarRocks Helm release (operator and cluster), and catalog initialization job.
This setting takes precedence over additional Helm values so the UI and
StarRocks deployment stay consistent. Polaris remains available for other services.

For existing deployments, set `enabled = true` before applying to retain
Data Explorer. Applying with the default `false` removes the existing StarRocks
release. A Terraform state migration preserves the release when enabled.

## Read-only orchestration server

`orchestration.read_only.enabled` defaults to false. AWS and Azure wrappers fill
`database_host` with the managed read replica and `verticle_class` with their
HTTP-only verticle. With a direct module call, supply both explicitly. The module
rejects an absent replica address, the primary database host, or multiple verticles.

Optional `replicas`, `resources`, and `ingress` configure the separate deployment.
Ingress is disabled by default; enabling it requires a unique hostname and any
needed TLS configuration. The reader shares the primary image/tag and existing
DB Secret, and receives `ORCHESTRATION_READ_ONLY=true`. Its separate service
account has no cloud identity annotations/RBAC and does not mount a Kubernetes
token. Writer runtime environment and pod identity labels are not copied.

Use a platform image release containing read-only mode before enabling the chart.
The reader supports PostgreSQL metadata inspection only; authentication continues
through the existing frontend. The final Helm values preserve the Terraform
reader settings even if generic extra Helm values attempt to override them.
