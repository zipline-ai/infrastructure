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

## Required Overrides

At minimum, each Terraform module should provide:

- `global.customer_name`
- `global.version`
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

StarRocks stores only its own metadata and local cache in the `starrocks-data`
PVC. Configure `starrocks.persistence.storageClass` and
`starrocks.persistence.size` when the cluster's default StorageClass is not
appropriate.

## Validation

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
