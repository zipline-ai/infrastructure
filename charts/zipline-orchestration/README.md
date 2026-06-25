# Zipline Orchestration Chart

This chart is the shared Kubernetes deployment artifact for Zipline orchestration and Crucible compute. It was ported from the `infra-aws-prod` orchestration chart and is intended to be reused by each cloud Terraform module.

The chart renders:

- Hub, UI, Eval, and optional Fetcher services
- Ingress controllers and ingress resources for the public service endpoints
- Spark operator, Spark driver RBAC, Spark History Server, Loki, and Promtail
- Polaris catalog bootstrap and RBAC reconciliation
- Compute namespaces, quotas, priority classes, image prepull, warm pool, and optional NVMe setup

## Cloud Boundary

The chart does not branch on a cloud provider. Cloud-specific infrastructure is supplied through values by Terraform:

- `serviceAccount.annotations` and `podLabels` for workload identity
- `secrets.provider`, `secrets.parameters`, and `secrets.secretObjects` for the CSI Secrets Store driver
- `database.*` and `database.credentialsSecret.*` for Postgres connectivity
- `compute.objectStore.*`, `compute.sparkDefaults.eventLogDir`, and Loki storage settings for object storage
- `polaris.bootstrap.rbac.catalog.storage.*` for Polaris storage config
- ingress controller service annotations for load balancer behavior
- `ingress.*.tls` for Kubernetes TLS secrets when TLS terminates at ingress-nginx
- `runtime.env` and service-specific `orchestration.*.env` for application runtime settings

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
- `secrets.provider` when `secrets.enabled=true`

`compute.objectStore.bucket` is the bucket or container name only. Do not pass an object-store URI there; pass full provider-native paths only to values that expect paths, such as Spark event logs or Polaris base locations.

## Validation

Render the chart with explicit overrides before wiring a cloud module:

```sh
helm template zipline charts/zipline-orchestration \
  --namespace zipline-system \
  --set global.customer_name=test-customer \
  --set global.version=test \
  --set secrets.provider=test \
  --set database.host=postgres.example.com \
  --set compute.objectStore.bucket=test-bucket \
  --set compute.sparkDefaults.eventLogDir=test-bucket/spark-events \
  --set polaris.bootstrap.rbac.catalog.storage.type=S3 \
  --set orchestration.hub.image=ziplineai/hub \
  --set orchestration.hub.verticleClass=com.zipline.OrchestrationVerticle \
  --set orchestration.eval.image=ziplineai/eval
```
