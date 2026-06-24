# Azure Zipline Orchestration

Installs the shared `charts/zipline-orchestration` chart on AKS and wires Azure
infrastructure into cloud-neutral chart values.

Azure-specific work stays at this layer:

- Azure workload identity annotations and pod labels.
- Azure Key Vault objects projected through the generic chart `secrets` values.
- Static IP and resource-group settings for ingress-nginx controller Services.
- ABFS event log, warehouse, and Flink state paths supplied as runtime values.

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

Initialize this wrapper with:

```shell
tofu init -reconfigure -backend-config=backend.hcl
```

If the remote canary inputs need to be updated intentionally, edit the local
ignored files and run:

```shell
./push_crucible_config.sh
```
