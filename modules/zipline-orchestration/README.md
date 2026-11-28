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

Team compute namespaces are provisioned automatically when teams sync to the
Hub. There is no separate `orchestration.compute.team_namespaces_enabled`
setting. Set `orchestration.compute.rbac_create = false` only when the Hub's
namespace-provisioner permissions and shared compute ClusterRoles are managed
externally. The namespace template remains installed in that mode; see the
[chart's team namespace requirements](../../charts/zipline-orchestration/README.md#team-compute-namespaces).

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

## Use a client-managed Loki-compatible backend

Merge the following into your existing AWS, Azure, or GKE `.tfvars`:

```hcl
orchestration = {
  logging = {
    loki_query_url = "https://logs.example.com"
  }
}
```

Set `loki_query_url` to the base URL. Hub and UI append
`/loki/api/v1/query_range`. The endpoint must be reachable from their pods
and support GET and POST range queries with LogQL. Put the endpoint behind
client-managed network controls or a gateway that supplies any upstream
authentication and tenant headers. Remove any manual `LOKI_URL` environment
override so Hub and UI use the configured endpoint.

Zipline skips the bundled Loki and Promtail when this setting is present.
Configure your collector to send Hub and compute pod logs to your backend
before switching. Preserve the Kubernetes stream labels `namespace`, `pod`,
and `container`, the `app` and `component` labels for Flink, and the
`chronon_job_id` and `spark_role` labels where present. Extract `workflowId`
and `stepId` from Hub log entries as structured metadata so the built-in
workflow and step filters continue to work.

When migrating a deployment, verify that the external backend receives logs
with these labels. Back up or migrate any history you need before applying:
Helm removes the bundled Loki resources, including its PVC if one was created.
After applying, verify that Hub and UI can retrieve job logs and that the UI
can retrieve workflow and step logs. Omit the setting to use bundled logging.
