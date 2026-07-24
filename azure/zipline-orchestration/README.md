# Azure Zipline Orchestration

Creates the Azure cloud primitives for Zipline orchestration, installs the shared
`charts/zipline-orchestration` chart on AKS, and wires Azure infrastructure into
cloud-neutral chart values.

This wrapper owns Azure resources such as AKS, Azure Database for PostgreSQL,
Key Vault, storage containers, workload identity, Azure Container Registry pull
access, Azure Monitor managed Prometheus, and Azure load balancer integrations
for ingress-nginx. The shared `modules/zipline-orchestration` module owns the
common Helm values and chart installation behavior.

DNS records are intentionally not managed here. After apply, use the
`ingress_load_balancer_target` output in the DNS automation for the target
environment.

## Configuration Files

Supply environment-specific values through local, git-ignored Terraform variable
files. The root accepts two top-level objects:

- `orchestration`: shared Zipline installation settings.
- `azure`: Azure-specific infrastructure settings.

A minimal starting point looks like this:

```hcl
orchestration = {
  deployment = {
    customer_name   = "example"
    artifact_prefix = "abfss://artifacts@example.dfs.core.windows.net/zipline/artifacts"
    zipline_version = "example-version"
  }

  ingress = {
    domain = "zipline.example.com"
  }
}

azure = {
  location                 = "westus2"
  tenant_id                = "00000000-0000-0000-0000-000000000000"
  warehouse_container_name = "warehouse"
  storage_account_name     = "examplestorage"
}
```

Run with a backend configured for the target environment:

```shell
../../pull_crucible_config.sh azure
tofu init -reconfigure -backend-config=backend.hcl
```

## Required Inputs

Set these for every environment.

| Field | Why it is required |
| --- | --- |
| `orchestration.deployment.customer_name` | Used as the environment/customer prefix for generated resources. |
| `orchestration.deployment.artifact_prefix` | ABFS/WASBS URI for Zipline artifacts. The wrapper creates the container portion of this URI. |
| `orchestration.deployment.zipline_version` | Image tag used across Zipline services. |
| `orchestration.ingress.domain` | Public host used by the UI, Hub, Eval, and supporting ingress routes. |
| `azure.location` | Azure region for the resource group and regional resources. |
| `azure.tenant_id` | Azure tenant used by workload identity and Key Vault integration. |
| `azure.warehouse_container_name` | Storage container for the warehouse. The wrapper creates this container. |
| `azure.storage_account_name` | Existing Azure Storage account that contains the Zipline containers. |

The artifact prefix must be a container-scoped URI such as
`abfss://artifacts@example.dfs.core.windows.net/zipline/artifacts`.

## Optional Inputs

Most optional fields have production-oriented defaults. Add them only when the
environment needs behavior different from the default.

### Installation

Use these when the Helm release or Kubernetes namespace needs a non-default
shape.

| Field | Default | Use when |
| --- | --- | --- |
| `orchestration.install.release_name` | `zipline-orchestration` | You need a different Helm release name. |
| `orchestration.install.namespace` | `zipline-system` | You install Zipline into a different namespace. |
| `orchestration.install.create_namespace` | `true` | The namespace is created outside Terraform. |
| `orchestration.install.namespace_labels` | `{}` | The namespace needs labels such as admission or ownership metadata. |
| `orchestration.install.namespace_annotations` | `{}` | The namespace needs annotations. |
| `orchestration.install.helm_wait` | `true` | You want to disable Helm waiting during iterative development. |
| `orchestration.install.helm_timeout` | `300` | The release needs more or less time to become ready. |
| `orchestration.install.atomic` | `false` | You want Helm to roll back failed upgrades automatically. |
| `orchestration.install.cleanup_on_fail` | `false` | You want Helm to delete newly-created resources after a failed upgrade. |
| `orchestration.install.dependency_update` | `false` | You want Helm to update chart dependencies during install. |

### Images and Pull Secrets

The default Spark and Flink images are public defaults. Configure a pull secret
when the environment pulls from a private Docker Hub image or needs authenticated
pulls.

| Field | Default | Use when |
| --- | --- | --- |
| `orchestration.image_pull_secret.name` | `docker-hub-creds` | A Kubernetes image pull Secret already exists, or you want a custom generated Secret name. |
| `orchestration.image_pull_secret.create` | `false` | Terraform should create the Docker Hub pull Secret. |
| `orchestration.image_pull_secret.dockerhub_username` | `ziplineai` | The pull token belongs to a different Docker Hub user. |
| `orchestration.image_pull_secret.dockerhub_token` | `""` | Required when `create = true`. |
| `orchestration.compute.spark_image` | `ziplineai/spark:nightly` | You need a pinned or custom Spark image. |
| `orchestration.compute.flink_image` | `ziplineai/flink:1.20.3` | You need a pinned or custom Flink image. |
| `orchestration.hub.image` | Azure wrapper default | You need to override the Azure Hub image. |
| `orchestration.eval.image` | Azure wrapper default | You need to override the Azure Eval image. |

### Ingress and TLS

By default, the wrapper creates an Azure Load Balancer for ingress-nginx and the
shared chart creates Kubernetes Ingress resources for
`orchestration.ingress.domain`. TLS termination is expected to happen at
ingress-nginx through Kubernetes TLS Secrets.

| Field | Default | Use when |
| --- | --- | --- |
| `orchestration.ingress.class_name` | `nginx-ui` | You use a different ingress class. |
| `orchestration.ingress.tls_secret_name` | `zipline-tls-secret` | A different Kubernetes TLS Secret should be attached to app ingresses. |
| `orchestration.ingress.cert_manager_cluster_issuer` | `letsencrypt-prod` | cert-manager should use a different ClusterIssuer. |
| `orchestration.ingress.create_cluster_issuer` | `false` | The chart should create the ClusterIssuer. |
| `orchestration.ingress.cluster_issuer_email` | `""` | Required by ACME when creating a ClusterIssuer. |
| `orchestration.ingress.cluster_issuer_server` | Let's Encrypt production | You need staging ACME or another ACME server. |
| `orchestration.ingress.cluster_issuer_secret_name` | `""` | You want a specific ACME account private-key Secret name. |
| `orchestration.ingress.cluster_issuer_ingress_class` | ingress class name | The HTTP-01 solver should use a different ingress class. |
| `orchestration.ingress.annotations` | `{}` | App ingresses need extra annotations. |
| `azure.ingress_load_balancer_ip` | dynamic IP | Ingress-nginx should use a pre-created static public IP. |
| `azure.load_balancer_resource_group` | AKS node resource group | The static public IP lives in a different resource group. |

Azure Application Gateway or Front Door can be layered in front of ingress-nginx
without changing the shared chart boundary.

### Authentication

Authentication is disabled unless `orchestration.auth.enabled = true`. When auth
is enabled, the Azure wrapper expects auth secret values to exist in Key Vault
with the names used by the shared chart.

The expected Key Vault secret names are:

- `auth-secret`
- `google-oauth-client-secret`
- `github-oauth-client-secret`
- `microsoft-entra-oauth-client-secret`
- `sso-client-secret`
- `sso-saml-cert`, only when `orchestration.auth.sso_use_saml = true`

Set only the auth provider fields that the environment uses:

| Field | Use when |
| --- | --- |
| `orchestration.auth.url` | The auth callback/public URL differs from the UI origin default. |
| `orchestration.auth.google_oauth_client_id` | Google OAuth is enabled. |
| `orchestration.auth.github_oauth_client_id` | GitHub OAuth is enabled. |
| `orchestration.auth.microsoft_entra_tenant_id` | Microsoft Entra auth is enabled. |
| `orchestration.auth.microsoft_entra_oauth_client_id` | Microsoft Entra auth is enabled. |
| `orchestration.auth.sso_provider_id` | SSO provider metadata is required by Zipline. |
| `orchestration.auth.sso_domain` | SSO provider metadata is required by Zipline. |
| `orchestration.auth.sso_issuer` | OIDC SSO is enabled. |
| `orchestration.auth.sso_client_id` | OIDC SSO is enabled. |
| `orchestration.auth.sso_use_saml` | SAML SSO is enabled instead of OIDC. |
| `orchestration.auth.sso_saml_entry_point` | SAML SSO is enabled. |
| `orchestration.auth.sso_saml_issuer` | SAML SSO is enabled. |
| `orchestration.auth.sso_saml_callback_url` | SAML SSO needs an explicit callback URL. |
| `orchestration.auth.idp_role_mapping` | IdP roles or groups need to map to Zipline roles. |
| `orchestration.auth.idp_group_claim` | The IdP uses a custom group claim. |

### Compute Namespaces

The default compute namespace is `zipline-default` for team `default`. Change
these values when an environment needs more than one compute namespace or custom
namespace policy.

| Field | Default | Use when |
| --- | --- | --- |
| `orchestration.compute.default_namespace` | `zipline-default` | Jobs should default to another namespace. |
| `orchestration.compute.namespaces` | `[{ name = "zipline-default", team = "default" }]` | You need multiple compute namespaces or team labels. |
| `orchestration.compute.namespace_defaults` | `{}` | Compute namespaces need default labels, annotations, ResourceQuota, or LimitRange settings. |
| `orchestration.compute.spark_service_account` | `spark-operator-spark` | Spark jobs use a non-default service account name. |
| `orchestration.compute.flink_service_account` | `flink` | Flink jobs use a non-default service account name. |
| `orchestration.compute.rbac_create` | `true` | RBAC is managed outside this chart. |
| `orchestration.compute.image_prepull_enabled` | `true` | You want to disable image prepull. |
| `orchestration.compute.image_prepull_images` | Spark image | You want to prepull additional or different images. |
| `orchestration.compute.warm_pool` | disabled | You need to pre-warm Spark driver capacity. |
| `orchestration.compute.system_priority_class` | disabled | Compute support workloads need a PriorityClass. |

Do not set `orchestration.compute.object_store.bucket` to an ABFS/WASBS URI. The
Azure wrapper supplies the warehouse container and region from
`azure.warehouse_container_name` and `azure.location`.

### AKS Capacity

The wrapper creates an AKS cluster with workload identity enabled. The default
node pool is intended to be a general-purpose starting point, and optional user
node pools can be added through `azure.node_pools`.

| Field | Default | Use when |
| --- | --- | --- |
| `azure.subscription_id` | active Azure CLI/default subscription | Terraform should target a specific subscription. |
| `azure.resource_group_name` | `<customer_name>-crucible-rg` | You need a stable or pre-created resource group name. |
| `azure.cluster_name` | `<customer_name>-aks` | You need a stable or pre-approved AKS cluster name. |
| `azure.kubernetes_version` | `1.36.1` | The environment must pin a different Kubernetes version. |
| `azure.aks_dns_prefix` | cluster name | The AKS DNS prefix should differ from the cluster name. |
| `azure.default_node_pool` | generated defaults | The default node pool needs different size, count, disk, scaling, or OS settings. |
| `azure.node_pools` | `{}` | The cluster needs additional user node pools. |

Default node pool overrides include `name`, `vm_size`, `node_count`,
`min_count`, `max_count`, `os_disk_size_gb`, `os_disk_type`, `os_sku`, and
`auto_scaling_enabled`.

Each `azure.node_pools` entry supports the AKS node pool fields used by the
wrapper, including `vm_size`, `mode`, `auto_scaling_enabled`, `node_count`,
`min_count`, `max_count`, `os_sku`, `os_disk_type`, `os_disk_size_gb`,
`priority`, `eviction_policy`, `spot_max_price`, `node_labels`, and
`node_taints`.

### Network

When no existing network objects are supplied, the wrapper creates a VNet with
an AKS subnet and a private-endpoints subnet.

| Field | Default | Use when |
| --- | --- | --- |
| `azure.vnet_address_space` | `["10.0.0.0/16"]` | The VNet CIDR must fit an existing network plan. |
| `azure.aks_subnet_address_prefixes` | `["10.0.0.0/22"]` | AKS needs a different subnet CIDR. |
| `azure.private_endpoints_subnet_address_prefix` | `10.0.5.0/24` | Private endpoints need a different subnet CIDR. |
| `azure.aks_service_cidr` | `172.20.0.0/16` | The Kubernetes service CIDR must avoid overlap. |
| `azure.aks_dns_service_ip` | `172.20.0.10` | The Kubernetes DNS service IP must match the service CIDR. |
| `azure.aks_pod_cidr` | `10.244.0.0/16` | Overlay pods need a different CIDR. |

### Storage and IAM Grants

The wrapper creates the artifact, warehouse, and logs containers in an existing
storage account. It grants the Zipline workload identity access to that account.

| Field | Default | Use when |
| --- | --- | --- |
| `azure.storage_account_resource_group` | orchestration resource group | The storage account lives in a different resource group. |
| `azure.logs_container_name` | `zipline-logs-<customer_name>` | You need a specific logs container name. |
| `azure.storage_path_prefix` | `""` | Warehouse paths should be nested under a prefix. |
| `azure.storage_role_definition_names` | `["Storage Blob Data Contributor"]` | The workload identity needs different storage roles. |
| `azure.resource_group_role_definition_names` | `[]` | The workload identity needs extra roles on the orchestration resource group. |

### Database

The Azure wrapper creates Azure Database for PostgreSQL Flexible Server and
supplies the shared chart database connection values. Override these only when
the default database shape is not right for the environment.

| Field | Default | Use when |
| --- | --- | --- |
| `azure.database_host` | created server FQDN | Zipline should use an externally managed database. |
| `azure.database_location` | `azure.location` | The database should be created in a different Azure region. |
| `azure.database_name` | `execution_info` or `orchestration.database.name` | Zipline should use a different database name. |
| `azure.database_port` | `5432` | The database listens on a different port. |
| `azure.database_server_name` | `<customer_name>-zipline-orch-instance` | The PostgreSQL server needs a specific name. |
| `azure.database_admin_username` | `locker_user` | The admin username should change. |
| `azure.database_version` | `16` | PostgreSQL should use a different major version. |
| `azure.database_sku_name` | `B_Standard_B1ms` | PostgreSQL needs more or less capacity. |
| `azure.database_storage_mb` | `32768` | PostgreSQL needs a different storage size in MB. |
| `azure.database_backup_retention_days` | `7` | Backups need a different retention period. |
| `azure.database_public_network_access_enabled` | `false` | The database must be publicly accessible. |

### Key Vault and Secrets

The wrapper configures External Secrets Operator against Azure Key Vault for
database and auth secrets. It also writes the generated database credentials
into Key Vault.

| Field | Default | Use when |
| --- | --- | --- |
| `azure.keyvault_name` | `<customer_name>-zipline-secrets` | You need a stable or pre-created Key Vault name. |
| `azure.workload_identity_name` | `<customer_name>-workload-identity` | You need a stable workload identity name. |
| `azure.workload_identity_client_id` | created identity client ID | You use an externally managed user-assigned identity. |
| `azure.database_credentials_secret_name` | `<customer_name>-postgres-credentials` | The Kubernetes database Secret needs a specific name. |
| `azure.database_username_secret_name` | `pg-admin-username` | Key Vault stores the DB username under a different secret name. |
| `azure.database_password_secret_name` | `pg-admin-password` | Key Vault stores the DB password under a different secret name. |
| `orchestration.secrets.extra_external_secrets` | none | You need additional `ExternalSecret` resources. |
| `orchestration.secrets.secret_store` | Azure Key Vault SecretStore | You need to customize the generated SecretStore. |
| `orchestration.secrets.external_secrets_enabled` | `true` | External Secrets Operator is managed differently or disabled. |

### Container Registry

Use these when AKS needs pull permissions for a private Azure Container Registry.

| Field | Default | Use when |
| --- | --- | --- |
| `azure.container_registry_name` | `""` | AKS should receive AcrPull on an Azure Container Registry. |
| `azure.container_registry_resource_group` | orchestration resource group | The registry lives in a different resource group. |

### Observability

The wrapper enables AKS managed Prometheus, creates an Azure Monitor workspace,
associates the workspace default collection endpoint and rule with the AKS
cluster, grants the Zipline workload identity Monitoring Reader on the
workspace, annotates Hub pods for scraping, and passes the workspace PromQL query
endpoint to the UI with `METRICS_PROVIDER=azure`.

| Field | Default | Use when |
| --- | --- | --- |
| `azure.monitor_workspace_name` | `<customer_name>-prometheus` | You need a specific Azure Monitor workspace name. |
| `azure.monitor_workspace_public_network_access` | `true` | The workspace query endpoint should not be publicly reachable. |
| `azure.monitor_metrics_annotations_allowed` | provider default | AKS managed Prometheus should only preserve specific annotations. |
| `azure.monitor_metrics_labels_allowed` | provider default | AKS managed Prometheus should only preserve specific labels. |
| `orchestration.prometheus.query_endpoint` | Azure Monitor workspace endpoint | You need to override the UI Prometheus query endpoint. |

Hub metrics default to Chronon's Prometheus reader on port `8905`. The wrapper
adds the standard `prometheus.io/scrape`, `prometheus.io/port`, and
`prometheus.io/path` annotations when that reader is enabled.

### Addons

The shared module installs common Kubernetes addons by default.

| Field | Default | Use when |
| --- | --- | --- |
| `orchestration.addons.install_external_secrets_operator` | `true` | External Secrets Operator is installed elsewhere. |
| `orchestration.addons.install_cert_manager` | `true` | cert-manager is installed elsewhere or not needed. |
| `orchestration.addons.install_flink_operator` | `true` | Flink operator is installed elsewhere or not needed. |
| `orchestration.addons.install_opentelemetry_operator` | `false` | OpenTelemetry operator should be installed. |
| `orchestration.addons.external_secrets_operator_values` | `{}` | The External Secrets Operator Helm release needs custom values. |
| `orchestration.addons.cert_manager_values` | `{}` | The cert-manager Helm release needs custom values. |

### Runtime and Advanced Helm Overrides

Use these as escape hatches for environment-specific behavior that is not
covered by a typed input above.

| Field | Use when |
| --- | --- |
| `orchestration.runtime_env` | Environment variables should be added to all services. |
| `orchestration.hub_env` | Hub needs extra environment variables. |
| `orchestration.ui_env` | UI needs extra environment variables. |
| `orchestration.fetcher_env` | Fetcher needs extra environment variables. |
| `orchestration.eval_env` | Eval needs extra Eval environment variables. |
| `orchestration.hub.pod_annotations` | Hub pods need additional annotations, such as scrape annotations. |
| `orchestration.hub.chronon_metrics_reader` | Hub metrics should use a reader other than the Prometheus default. |
| `orchestration.hub.metrics_port` | Hub Prometheus metrics should expose a different port. |
| `orchestration.hub.data_quality_metrics_dataset` | Hub should publish data-quality metrics to a specific dataset. |
| `orchestration.ui.origin` | The public UI origin differs from `https://<ingress.domain>`. |
| `orchestration.deployment.deploy_fetcher` | The optional fetcher service should be deployed. |
| `orchestration.values` | Raw Helm values should be merged before provider values. |
| `orchestration.extra_values` | Raw Helm values should be merged after typed and provider values. |
| `orchestration.extra_values_yaml` | Raw Helm values are easier to provide as YAML strings. |

Prefer typed inputs over raw Helm values. Use `extra_values` for intentional
one-off overrides that should remain local to an environment.

## Outputs

The most commonly used outputs are:

| Output | Use |
| --- | --- |
| `ingress_load_balancer_hostname` | Inspect the public ingress load balancer hostname, when Azure provides one. |
| `ingress_load_balancer_ip` | Inspect the public ingress load balancer IP. |
| `ingress_load_balancer_target` | Create the external DNS record for `orchestration.ingress.domain`. |
| `artifact_container_name` | Confirm the artifact container created from `artifact_prefix`. |
| `warehouse_container_name` | Confirm the warehouse container. |
| `logs_container_name` | Confirm the logs container. |
| `resource_group_name` | Inspect or integrate the orchestration resource group. |
| `aks_cluster_name` | Configure or inspect the created AKS cluster. |
| `aks_oidc_issuer_url` | Inspect workload identity federation settings. |
| `keyvault_name` | Inspect or integrate the Azure Key Vault used for secrets. |
| `postgres_fqdn` | Inspect the PostgreSQL server hostname. |
| `workload_identity_client_id` | Inspect the workload identity used by orchestration and compute pods. |
| `monitor_workspace_id` | Inspect or integrate the Azure Monitor workspace. |
| `prometheus_query_endpoint` | Confirm the PromQL query endpoint passed to the Zipline UI. |

## Notes

The shared Helm chart bootstraps Polaris runtime authentication. On each install
or upgrade, the Polaris bootstrap hook reconciles a non-root `chronon`
principal, grants it access to the seeded catalog role, writes its
`client_id:client_secret` value into the `polaris-client-credentials`
Kubernetes Secret as `OC_CREDENTIAL`, and restarts Hub so Spark catalog
placeholders can be resolved without customer-supplied Polaris credentials.
