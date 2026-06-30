# Azure Zipline Orchestration

Installs the shared `charts/zipline-orchestration` chart on AKS and wires Azure
infrastructure into cloud-neutral chart values.

Azure-specific work stays at this layer:

- Azure workload identity annotations and pod labels.
- Azure Key Vault objects projected through the generic chart `secrets` values.
- Static IP and resource-group settings for ingress-nginx controller Services.
- Artifact, warehouse, and logs storage containers in the configured Azure
  storage account.
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

Supported shared fields:

| Field | Notes |
| --- | --- |
| `orchestration.install.release_name` | Helm release name. |
| `orchestration.install.namespace` | Kubernetes namespace. |
| `orchestration.install.create_namespace` | Whether Terraform creates the namespace. |
| `orchestration.install.namespace_labels` | Labels for the namespace when created. |
| `orchestration.install.namespace_annotations` | Annotations for the namespace when created. |
| `orchestration.install.helm_wait` | Wait for Helm resources to become ready. |
| `orchestration.install.helm_timeout` | Helm timeout in seconds. |
| `orchestration.install.atomic` | Enable atomic Helm upgrades. |
| `orchestration.install.cleanup_on_fail` | Clean up failed Helm upgrades. |
| `orchestration.install.dependency_update` | Update Helm chart dependencies during install. |
| `orchestration.deployment.customer_name` | Customer or environment name used in rendered resources. |
| `orchestration.deployment.artifact_prefix` | Artifact ABFS/WASBS URI. Terraform creates the container portion of this URI. |
| `orchestration.deployment.zipline_version` | Image tag used across Zipline services. |
| `orchestration.deployment.deploy_fetcher` | Whether to deploy the optional fetcher service. |
| `orchestration.database.host` | Postgres host. |
| `orchestration.database.port` | Postgres port. |
| `orchestration.database.name` | Postgres database name. |
| `orchestration.database.ssl_mode` | Postgres SSL mode. |
| `orchestration.database.jdbc_url` | Optional explicit JDBC URL. |
| `orchestration.database.url` | Optional explicit database URL. |
| `orchestration.database.credentials_secret.name` | Kubernetes Secret containing DB credentials. |
| `orchestration.database.credentials_secret.username_key` | Username key in the DB Secret. |
| `orchestration.database.credentials_secret.password_key` | Password key in the DB Secret. |
| `orchestration.ingress.domain` | Public domain for UI, Hub, Eval, and supporting routes. |
| `orchestration.ingress.class_name` | Ingress class used by shared Ingress resources. |
| `orchestration.ingress.tls_secret_name` | Kubernetes TLS Secret for ingress-nginx TLS termination. |
| `orchestration.ingress.cert_manager_cluster_issuer` | cert-manager ClusterIssuer name. |
| `orchestration.ingress.create_cluster_issuer` | Whether the chart creates the ClusterIssuer. |
| `orchestration.ingress.cluster_issuer_email` | ACME registration email when creating the ClusterIssuer. |
| `orchestration.ingress.cluster_issuer_server` | ACME server URL. |
| `orchestration.ingress.cluster_issuer_secret_name` | Optional ACME account private-key Secret name. |
| `orchestration.ingress.cluster_issuer_ingress_class` | Optional HTTP-01 solver ingress class. |
| `orchestration.ingress.annotations` | Extra annotations applied to shared app ingresses. |
| `orchestration.auth.enabled` | Enable UI auth integration. |
| `orchestration.auth.url` | Public UI auth URL. |
| `orchestration.auth.google_oauth_client_id` | Google OAuth client ID. |
| `orchestration.auth.github_oauth_client_id` | GitHub OAuth client ID. |
| `orchestration.auth.microsoft_entra_tenant_id` | Microsoft Entra tenant ID. |
| `orchestration.auth.microsoft_entra_oauth_client_id` | Microsoft Entra OAuth client ID. |
| `orchestration.auth.sso_provider_id` | SSO provider ID. |
| `orchestration.auth.sso_domain` | SSO domain. |
| `orchestration.auth.sso_issuer` | OIDC SSO issuer. |
| `orchestration.auth.sso_client_id` | OIDC SSO client ID. |
| `orchestration.auth.sso_use_saml` | Use SAML instead of OIDC for SSO. |
| `orchestration.auth.sso_saml_entry_point` | SAML entry point. |
| `orchestration.auth.sso_saml_issuer` | SAML issuer. |
| `orchestration.auth.sso_saml_callback_url` | SAML callback URL. |
| `orchestration.auth.idp_role_mapping` | IdP role-to-Zipline-role mapping. |
| `orchestration.auth.idp_group_claim` | IdP group claim name. |
| `orchestration.compute.default_namespace` | Default compute namespace. |
| `orchestration.compute.namespaces` | Compute namespaces and team labels. |
| `orchestration.compute.spark_image` | Spark image. |
| `orchestration.compute.flink_image` | Flink image. |
| `orchestration.compute.spark_service_account` | Spark compute service account name. |
| `orchestration.compute.flink_service_account` | Flink compute service account name. |
| `orchestration.compute.spark_event_log_dir` | Spark event log path. |
| `orchestration.compute.rbac_create` | Whether to create compute RBAC. |
| `orchestration.compute.image_prepull_enabled` | Enable image prepull DaemonSet. |
| `orchestration.compute.image_prepull_images` | Images to prepull. |
| `orchestration.compute.history_server_image` | Spark History Server image. |
| `orchestration.compute.history_server_options` | Spark History Server JVM options. |
| `orchestration.compute.spark_defaults` | Extra chart values for Spark defaults. |
| `orchestration.compute.flink_defaults` | Extra chart values for Flink defaults. |
| `orchestration.compute.object_store.bucket` | Warehouse bucket/container name only, not a URI. |
| `orchestration.compute.object_store.region` | Warehouse object-store region/location. |
| `orchestration.compute.service_account.annotations` | Compute service account annotations. |
| `orchestration.compute.image_prepull_overrides` | Extra chart values for image prepull. |
| `orchestration.image_pull_secret.name` | Image pull Secret name. |
| `orchestration.image_pull_secret.create` | Whether Terraform creates the Docker Hub Secret. |
| `orchestration.image_pull_secret.dockerhub_username` | Docker Hub username when creating the Secret. |
| `orchestration.image_pull_secret.dockerhub_token` | Docker Hub token when creating the Secret. |
| `orchestration.addons.install_external_secrets_operator` | Install External Secrets Operator. |
| `orchestration.addons.install_cert_manager` | Install cert-manager. |
| `orchestration.addons.install_flink_operator` | Install Flink operator. |
| `orchestration.addons.install_opentelemetry_operator` | Install OpenTelemetry operator. |
| `orchestration.prometheus.query_endpoint` | Prometheus query endpoint. |
| `orchestration.secrets.secret_store` | External Secrets Operator SecretStore settings. |
| `orchestration.secrets.database_remote_refs.username` | ESO remoteRef for DB username. |
| `orchestration.secrets.database_remote_refs.password` | ESO remoteRef for DB password. |
| `orchestration.secrets.auth_remote_refs` | ESO remoteRefs for auth Secret keys. |
| `orchestration.secrets.extra_external_secrets` | Additional ExternalSecret resources. |
| `orchestration.service_account.create` | Whether to create the orchestration service account. |
| `orchestration.service_account.name` | Orchestration service account name. |
| `orchestration.service_account.annotations` | Orchestration service account annotations. |
| `orchestration.hub.chronon_metrics_reader` | Hub metrics reader mode. |
| `orchestration.hub.data_quality_metrics_dataset` | Data-quality metrics dataset name. |
| `orchestration.hub.image` | Hub image override. |
| `orchestration.hub.verticle_class` | Hub verticle class override. |
| `orchestration.hub.env` | Extra Hub environment variables. |
| `orchestration.ui.origin` | Explicit public UI origin. |
| `orchestration.eval.image` | Eval image override. |
| `orchestration.runtime_env` | Environment variables shared by services. |
| `orchestration.hub_env` | Extra Hub environment variables. |
| `orchestration.ui_env` | Extra UI environment variables. |
| `orchestration.fetcher_env` | Extra Fetcher environment variables. |
| `orchestration.eval_env` | Extra Eval environment variables. |
| `orchestration.values` | Raw Helm values merged before extra values. |
| `orchestration.extra_values` | Additional raw Helm values. |
| `orchestration.extra_values_yaml` | Additional raw Helm values YAML strings. |

Supported Azure-specific fields:

| Field | Notes |
| --- | --- |
| `azure.subscription_id` | Optional Azure subscription ID. Omit to use the authenticated Azure CLI/default subscription. |
| `azure.location` | Azure location. Required. |
| `azure.tenant_id` | Azure tenant ID. Required. |
| `azure.keyvault_name` | Key Vault name. Required. |
| `azure.workload_identity_client_id` | Workload identity client ID for Zipline pods. Required. |
| `azure.warehouse_container_name` | Warehouse storage container name. Terraform creates this container. Required. |
| `azure.logs_container_name` | Logs storage container name. Terraform creates this container. Defaults to `zipline-logs-<customer_name>`. |
| `azure.storage_account_name` | Storage account containing Zipline containers. Required. |
| `azure.database_password_secret_name` | Key Vault secret name for DB password. |
| `azure.database_username_secret_name` | Key Vault secret name for DB username. |
| `azure.storage_path_prefix` | Optional path prefix inside the warehouse container. |
| `azure.ingress_load_balancer_ip` | Static ingress load balancer IP. |
| `azure.load_balancer_resource_group` | Resource group for the ingress load balancer IP. |

The Azure wrapper creates the customer-owned artifact, warehouse, and logs
containers. Container names are supplied through
`orchestration.deployment.artifact_prefix`, `azure.warehouse_container_name`,
and `azure.logs_container_name`. The storage account remains an environment
input so installations can decide resource-group, ADLS/HNS, network access, and
private endpoint policy outside of the orchestration chart boundary.

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
  workload_identity_client_id = "00000000-0000-0000-0000-000000000000"
  warehouse_container_name    = "warehouse"
  logs_container_name         = "zipline-logs-example"
  storage_account_name        = "examplestorage"
}
```

Initialize this wrapper with:

```shell
az aks get-credentials --resource-group example-rg --name example-aks

tofu init -reconfigure -backend-config=backend.hcl
```
