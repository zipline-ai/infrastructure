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

## Use a client-managed ingress controller

Merge these settings into your existing `orchestration` input on AWS, Azure,
or GKE:

```hcl
orchestration = {
  ingress = {
    external_controller = true
    domain              = "zipline.example.com"
  }
}
```

Set `domain` to the hostname clients use over HTTPS. Zipline uses it to build
public URLs. Terraform skips the controller Service lookup, and the chart
skips ingress-nginx, Zipline's Ingress resources, the ingress ClusterIssuer,
and the Job that discovers the bundled load balancer address. GKE also skips
reserving an IP for the bundled controller. Use your controller's endpoint for
DNS. The Terraform outputs for the bundled load balancer are empty in this mode.

Create routes in your controller to the following Services in
`orchestration.install.namespace` (default `zipline-system`). These paths match
the chart defaults. If you change a path through Helm values, configure the
same path on your controller.

| Public path | Backend Service and port | Forwarding |
| --- | --- | --- |
| `/` | `orchestration-ui-service:80` | Preserve the path. |
| `/services/hub` | `orchestration-hub-service:80` | Strip the prefix. |
| `/services/eval` | `eval-service:80` | Strip the prefix. |
| `/services/fetcher` | `fetcher-service:80` | Strip the prefix. Add this route when Fetcher is enabled. |
| `/spark-history` | `spark-history-server:18080` | Strip the prefix on requests and add it back to backend redirects. |
| `/services/catalog` | `polaris-service:8181` | Map this prefix to `/api/catalog` if clients need public catalog access. |

Configure TLS and any route-level authentication in your controller. If Zipline
auth is enabled and users access Hub through a browser session, configure your
controller to forward-auth against `/auth/forward` on
`orchestration-ui-service:80`. Pass through the request's session cookie and
`Authorization` header, forward the returned `Authorization` header to Hub,
and route rejected browser sessions to the UI sign-in page. Preserve bearer
authentication for API clients.

When migrating an existing deployment, test your routes and TLS against the
client-managed endpoint before switching DNS and applying the opt-in setting.
The apply removes the bundled controller and routes. On GKE, it also releases
the Terraform-reserved ingress address if one was created for that controller.
