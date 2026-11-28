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

## Override workload images

Use the same `orchestration` input in your AWS, Azure, or GKE `.tfvars` file.
Merge the fields you need into your existing configuration. Omitted fields use
the deployment defaults.

```hcl
orchestration = {
  hub     = { image = "registry.example.com/zipline/hub" }
  eval    = { image = "registry.example.com/zipline/eval" }
  ui      = { image = "registry.example.com/zipline/web-ui" }
  fetcher = { image = "registry.example.com/zipline/chronon-fetcher" }

  compute = {
    spark_image          = "registry.example.com/zipline/spark:nightly"
    flink_image          = "registry.example.com/zipline/flink:1.20.3-spark4"
    history_server_image = "registry.example.com/zipline/spark:nightly"
    image_prepull_images = ["registry.example.com/zipline/spark:nightly"]
  }

  starrocks = {
    feImage = { repository = "registry.example.com/starrocks/fe-ubuntu", tag = "4.1.3" }
    cnImage = { repository = "registry.example.com/starrocks/cn-ubuntu", tag = "4.1.3" }
  }
}
```

Use repository names for Hub, Eval, UI, and Fetcher. UI and Fetcher use
`orchestration.deployment.zipline_version` as their tag. Hub and Eval use the
Spark 4 variant of that tag. Use Spark 4-compatible compute images. Compute image fields
take full image references. The history server and cost export use
`spark_image` by default. The pre-pull DaemonSet includes `spark_image` and
any additional images listed in `image_prepull_images`.

For the remaining workload and helper images, add a map with the relevant Helm
keys to `orchestration.extra_values`. These values layer on top of the wrapper's
cloud defaults. For example:

```hcl
extra_values = [{
  compute = {
    warmPool     = { image = "registry.example.com/pause:3.9" }
    imagePrepull = { pauseImage = "registry.example.com/pause:3.9" }
    loki         = { image = "registry.example.com/grafana/loki:3.4.2" }
  }
  orchestration = {
    setHubBaseUrl = { image = "registry.example.com/alpine/k8s:1.28.3" }
  }
  costExport       = { kubectlImage = "registry.example.com/alpine/k8s:1.28.3" }
  nodepoolExporter = { image = "registry.example.com/python:3.12-slim" }
  starrocks = {
    mysqlImage = "registry.example.com/mysql:8.0"
  }
  polaris = {
    image    = { repository = "registry.example.com/apache/polaris" }
    database = { initImage = "registry.example.com/postgres:16" }
    bootstrap = {
      image = { repository = "registry.example.com/apache/polaris-admin-tool" }
      rbac  = { image = { repository = "registry.example.com/python" } }
    }
  }
}]
```

If the `setHubBaseUrl.image` registry requires authentication, set
`orchestration.image_pull_secret.name` to an existing Secret in the Zipline
installation namespace with credentials for that registry.

Set `tag` alongside a Polaris image's `repository` to override its version.
The Polaris bootstrap image inherits the Polaris server tag when its own tag is
empty.

Set `orchestration.sandbox.image` to the Sandbox repository and
`orchestration.sandbox.egress.image` to the full egress proxy image reference
when you deploy Sandbox.
