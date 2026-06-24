# Azure Zipline Orchestration

Installs the shared `charts/zipline-orchestration` chart on AKS and wires Azure
infrastructure into cloud-neutral chart values.

Azure-specific work stays at this layer:

- Azure workload identity annotations and pod labels.
- Azure Key Vault objects projected through the generic chart `secrets` values.
- Static IP and resource-group settings for ingress-nginx controller Services.
- ABFS event log, warehouse, and Flink state paths supplied as runtime values.

The wrapper keeps the Terraform surface to Azure plumbing. Shared install inputs
live under the `orchestration` object and are consumed by
`modules/zipline-orchestration`; Azure-specific inputs remain flat in this root.
The chart owns service defaults such as per-service ingress annotations, image
repositories, and fetcher replicas. Use `orchestration.extra_values` only for
intentional one-off Helm overrides, such as a private registry mirror.

Networking intentionally matches AWS at the chart boundary: cloud load balancers
pass traffic to ingress-nginx, and Kubernetes Ingress TLS secrets own TLS
termination. Azure Application Gateway or Front Door can still be layered in
front later without changing the Zipline chart.

## Crucible Canary Overrides

Crucible Azure settings are stored outside the repo in Azure Blob Storage and
pulled locally when planning or applying:

```shell
./pull_crucible_config.sh
```

By default the script reads from storage account `ziplineai2`, container
`dev-zipline-vars`, and prefix `crucible-azure/zipline-orchestration`. Override
those with `AZURE_CONFIG_STORAGE_ACCOUNT`, `AZURE_CONFIG_CONTAINER`, and
`AZURE_CONFIG_PREFIX` if needed.

The script downloads two git-ignored files into this Terraform root:

- `backend.hcl`
- `crucible.auto.tfvars.json`

Common canary inputs should be grouped under `orchestration`, for example:

```hcl
orchestration = {
  install = {
    release_name = "claims-demo-hub"
    namespace    = "claims-demo-hub"
    helm_wait    = false
    helm_timeout = 900
  }
  deployment = {
    customer_name   = "claims-demo"
    artifact_prefix = "abfss://crucible@ziplineai2.dfs.core.windows.net/claims-demo/artifacts"
    zipline_version = "subdaily-sensor-fix-20260617235538"
  }
  database = {
    host     = "example.postgres.database.azure.com"
    name     = "execution-info"
    ssl_mode = "require"
  }
  ingress = {
    domain          = "crucible-azure.zipline.ai"
    tls_secret_name = "crucible-azure-tls"
  }
}
```

Initialize this wrapper with:

```shell
tofu init -reconfigure -backend-config=backend.hcl
```

If the remote canary inputs need to be updated intentionally, edit the local
ignored files and run:

```shell
./push_crucible_config.sh
```
