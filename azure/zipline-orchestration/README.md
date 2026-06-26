# Azure Zipline Orchestration

Installs the shared `charts/zipline-orchestration` chart on AKS and wires Azure
infrastructure into cloud-neutral chart values.

Azure-specific work stays at this layer:

- Azure workload identity annotations and pod labels.
- Azure Key Vault objects projected through the generic chart `secrets` values.
- Static IP and resource-group settings for ingress-nginx controller Services.
- ABFS event log and Polaris catalog paths supplied as runtime values.

The wrapper assumes the AKS cluster already has workload identity and the Azure
Key Vault CSI provider path available. It keeps the Terraform surface to Azure
orchestration plumbing. Shared install inputs live under the `orchestration`
object and are consumed by
`modules/zipline-orchestration`; Azure-specific inputs live under the `azure`
object.
Run this wrapper with a kubeconfig context already authenticated to the target
AKS cluster; Kubernetes and Helm providers use the standard local provider
configuration instead of discovering cluster credentials through Azure data
sources.
The shared module owns common service value generation such as image propagation,
compute defaults, and Polaris bootstrap defaults. Use `orchestration.extra_values`
only for intentional one-off Helm overrides, such as a private registry mirror.

Networking intentionally matches AWS at the chart boundary: cloud load balancers
pass traffic to ingress-nginx, and Kubernetes Ingress TLS secrets own TLS
termination. Azure Application Gateway or Front Door can still be layered in
front later without changing the Zipline chart.

## Inputs

Environment-specific settings should be supplied through local, git-ignored
Terraform variable files. Inputs are grouped into shared and provider-specific
objects:

Supported `orchestration` groups:

- `install`: `release_name`, `namespace`, `create_namespace`,
  `namespace_labels`, `namespace_annotations`, `helm_wait`, `helm_timeout`,
  `atomic`, `cleanup_on_fail`, `dependency_update`.
- `deployment`: `customer_name`, `artifact_prefix`, `zipline_version`,
  `deploy_fetcher`.
- `database`: `host`, `port`, `name`, `ssl_mode`, `jdbc_url`, `url`,
  `credentials_secret`.
- `ingress`: `domain`, `class_name`, `tls_secret_name`,
  `cert_manager_cluster_issuer`, `create_cluster_issuer`,
  `cluster_issuer_email`, `cluster_issuer_server`,
  `cluster_issuer_secret_name`, `cluster_issuer_ingress_class`,
  `annotations`.
- `auth`: `enabled`, `url`, OAuth/SAML provider settings, and IdP role/group
  mapping settings consumed by the shared chart.
- `compute`: namespaces, Spark/Flink images and service accounts, Spark event
  log path, image prepull settings, History Server settings, RBAC settings, and
  provider-specific Spark/Flink default overrides.
- `image_pull_secret`, `addons`, `prometheus`, `secrets`,
  `service_account`, `hub`, `ui`, `runtime_env`, `hub_env`, `ui_env`,
  `fetcher_env`, `eval_env`, `values`, `extra_values`, and
  `extra_values_yaml`.

Supported `azure` keys:

- Required: `location`, `tenant_id`, `keyvault_name`,
  `keyvault_identity_client_id`, `workload_identity_client_id`,
  `warehouse_container_name`, `storage_account_name`.
- Optional: `database_password_secret_name`, `database_username_secret_name`,
  `storage_path_prefix`, `ingress_load_balancer_ip`,
  `load_balancer_resource_group`.

```hcl
orchestration = {
  install = {
    release_name = "zipline-orchestration"
    namespace    = "zipline-system"
    helm_wait    = false
    helm_timeout = 900
  }
  deployment = {
    customer_name   = "example"
    artifact_prefix = "abfss://artifacts@example.dfs.core.windows.net/zipline/artifacts"
    zipline_version = "example-version"
  }
  database = {
    host     = "example.postgres.database.azure.com"
    name     = "execution-info"
    ssl_mode = "require"
  }
  ingress = {
    domain          = "zipline.example.com"
    tls_secret_name = "zipline-tls"
  }
}

azure = {
  location                    = "westus2"
  tenant_id                   = "00000000-0000-0000-0000-000000000000"
  keyvault_name               = "example-keyvault"
  keyvault_identity_client_id = "00000000-0000-0000-0000-000000000000"
  workload_identity_client_id = "00000000-0000-0000-0000-000000000000"
  warehouse_container_name    = "warehouse"
  storage_account_name        = "examplestorage"
}
```

Initialize this wrapper with:

```shell
az aks get-credentials --resource-group example-rg --name example-aks

tofu init -reconfigure -backend-config=backend.hcl
```
