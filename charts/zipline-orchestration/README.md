# Zipline Orchestration Chart

This chart is the shared Kubernetes deployment artifact for Zipline orchestration and Crucible compute. It was ported from the `infra-aws-prod` orchestration chart and is intended to be reused by each cloud Terraform module.

The chart renders:

- Hub, UI, Eval, and optional Fetcher services
- Ingress controllers and ingress resources for the public service endpoints
- Spark operator, Spark driver RBAC, Spark History Server, Loki, and Promtail
- Polaris catalog bootstrap and RBAC reconciliation
- StarRocks Data Explorer, initialized against the in-cluster Polaris Iceberg
  REST catalog
- Compute namespaces, quotas, priority classes, image prepull, and warm pool

## Cloud Boundary

The chart does not branch on a cloud provider. Cloud-specific infrastructure is supplied through values by Terraform:

- `serviceAccount.annotations` and `podLabels` for workload identity
- `secrets.externalSecrets.*` for External Secrets Operator SecretStores and ExternalSecrets
- `database.*` and `database.credentialsSecret.*` for Postgres connectivity
- `compute.objectStore.*`, `compute.sparkDefaults.eventLogDir`, and Loki storage settings for object storage
- `polaris.bootstrap.rbac.catalog.storage.*` for Polaris storage config
- ingress controller service annotations for load balancer behavior
- `ingress.*.tls` for Kubernetes TLS secrets when TLS terminates at ingress-nginx
- `runtime.env` and service-specific `orchestration.*.env` for application runtime settings
- `orchestration.hub.metricsReader`, `orchestration.hub.metricsPort`, and
  optional `orchestration.hub.podAnnotations` for Hub metrics exposure

## Spark 4 Runtime

Crucible has one compute runtime across every cloud. Spark jobs and the History
Server use `ziplineai/spark:nightly`, and Flink uses
`ziplineai/flink:1.20.3-spark4`. `CRUCIBLE_SPARK_IMAGE` and
`CRUCIBLE_FLINK_IMAGE` are chart-owned environment variables and cannot be set
through `runtime.env` or `orchestration.hub.env`.

`global.version` is the base service tag. Hub and Eval use its Spark 4 variant:
`nightly` stays `nightly`, while release and commit tags gain a `-spark4`
suffix. UI and Fetcher continue to use the base tag.

## Required Overrides

At minimum, each Terraform module should provide:

- `global.customer_name`
- `global.version` (the base tag before any `-spark4` suffix)
- `database.host`
- `orchestration.hub.image`
- `orchestration.hub.verticleClass`
- `orchestration.eval.image`
- `compute.objectStore.bucket`
- `compute.sparkDefaults.eventLogDir`
- `polaris.bootstrap.rbac.catalog.storage.type`
- `secrets.externalSecrets.secretStore` and `secrets.externalSecrets.targets` when the chart should create runtime Kubernetes Secrets

`compute.objectStore.bucket` is the bucket or container name only. Do not pass an object-store URI there; pass full provider-native paths only to values that expect paths, such as Spark event logs or Polaris base locations.

## Data Explorer

The chart always deploys StarRocks for the Data Explorer at
`starrocks-service:9030` and passes that endpoint to the web UI. Its
`zipline_catalog` external catalog is recreated after every install or upgrade
using the runtime credential created by Polaris. It connects to the
`polaris_<realm>` Polaris warehouse. The catalog uses the Iceberg
REST API, OAuth, and Polaris vended credentials, so it has no AWS-, Azure-, or
GCP-specific storage configuration. Query tables with fully qualified names,
for example `SELECT * FROM zipline_catalog.default.some_table LIMIT 100`.

StarRocks runs in shared-data mode: durable data is stored in the cloud object
store and CN Pods retain only a local cache. The CN pool is controlled by an HPA
with one to three replicas and 80% CPU/memory utilization targets. Configure
`starrocks.persistence.storageClass` and the FE/CN cache sizes when the
cluster's default StorageClass is not appropriate.

The Polaris runtime catalog role is granted `CATALOG_MANAGE_CONTENT`. This is
catalog-wide in Polaris: Data Explorer can discover namespaces and metadata
across the catalog, including namespaces created after bootstrap. Cloud
Terraform wrappers should pass this grant explicitly when they construct
provider values.

## Fetcher metrics

When `global.deploy_fetcher` is enabled, the fetcher defaults to the `prometheus`
metrics reader. It exposes Chronon metrics on the `chronon-metrics` container
port (8905) and Vert.x HTTP metrics on `vertx-metrics` (8906), both at `/metrics`.
The AWS wrapper scrapes both named ports directly. Metrics ports are not added
to the public Service or Ingress.

Set `orchestration.fetcher.metricsReader` to an empty string to disable metrics,
or to `http`/`grpc` to use an existing OTLP collector. Set `metricsPort` and
`vertxMetricsPort` under the same object to change the Prometheus ports.
Explicit `CHRONON_METRICS_READER`, `CHRONON_PROMETHEUS_SERVER_PORT`, and
`VERTX_PROMETHEUS_SERVER_PORT` entries in `runtime.env` or
`orchestration.fetcher.env` take precedence over these defaults. Fetcher env
entries take precedence over runtime env entries, as with other fetcher settings.

Use literal `value` entries for the reader when using direct scraping: Helm
cannot determine the reader from `valueFrom`, so it preserves that entry but
does not declare metrics ports. If a port uses `valueFrom`, set its chart port
to the same number so discovery matches the exporter.

## Compute workload quotas

The chart creates non-preempting `zipline-backfill` and `zipline-deploy`
PriorityClasses. Pods select one of these classes, and namespace ResourceQuotas
use the class name to account for backfill and deploy resources separately.

Mode quotas are initially enabled only for `zipline-default` through
`compute.modeResourceQuotas`. An empty mode `hard` map inherits the namespace's
aggregate `resourceQuota.hard` values, so enabling the scoped quotas does not
reduce existing capacity. Add another namespace key with explicit `hard` values
when extending mode quotas to another team.

## Validation

Run the fetcher rendering and AWS scrape discovery regression tests (requires
Helm and Python with PyYAML):

```sh
uv run --with PyYAML python -m unittest discover -s tests -v
```

Render the chart with explicit overrides before wiring a cloud module:

```sh
helm template zipline charts/zipline-orchestration \
  --namespace zipline-system \
  --set global.customer_name=test-customer \
  --set global.version=test \
  --set database.host=postgres.example.com \
  --set compute.objectStore.bucket=test-bucket \
  --set compute.sparkDefaults.eventLogDir=test-bucket/spark-events \
  --set polaris.bootstrap.rbac.catalog.storage.type=S3 \
  --set orchestration.hub.image=ziplineai/hub \
  --set orchestration.hub.verticleClass=com.zipline.OrchestrationVerticle \
  --set orchestration.eval.image=ziplineai/eval
```
