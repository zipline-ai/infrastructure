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
    flink_image          = "registry.example.com/zipline/flink:1.20.3"
    history_server_image = "registry.example.com/zipline/spark:nightly"
    image_prepull_images = ["registry.example.com/zipline/spark:nightly"]
  }

  starrocks = {
    feImage = { repository = "registry.example.com/starrocks/fe-ubuntu", tag = "4.1.3" }
    cnImage = { repository = "registry.example.com/starrocks/cn-ubuntu", tag = "4.1.3" }
  }
}
```

Use repository names for Hub, Eval, UI, and Fetcher. The chart appends
`orchestration.deployment.zipline_version` as their tag. Compute image fields
take full image references. The history server and image pre-pull list derive
their defaults from `spark_image`.

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

Set `tag` alongside a Polaris image's `repository` to override its version.
The Polaris bootstrap image inherits the Polaris server tag when its own tag is
empty.
