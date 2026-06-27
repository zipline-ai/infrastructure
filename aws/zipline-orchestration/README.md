# AWS Zipline Orchestration

Installs the shared `charts/zipline-orchestration` chart on EKS and wires AWS
infrastructure into cloud-neutral chart values.

AWS-specific work stays at this layer:

- IAM role annotations for orchestration and compute service accounts.
- AWS Secrets Manager objects projected through the generic chart
  `secrets` values.
- NLB annotations on the shared ingress-nginx controller Services.

The wrapper assumes the EKS cluster already has cluster-level AWS addons such as
the AWS Load Balancer Controller and AWS Secrets Store CSI provider installed.
It keeps the Terraform surface to AWS orchestration plumbing. Shared install
inputs live under the `orchestration` object and are consumed by
`modules/zipline-orchestration`; AWS-specific inputs live under the `aws`
object.
Run this wrapper with a kubeconfig context already authenticated to the target
EKS cluster; Kubernetes and Helm providers use the standard local provider
configuration instead of discovering cluster credentials through AWS data
sources.
The shared module owns common service value generation such as image propagation,
compute defaults, and Polaris bootstrap defaults. Use
`orchestration.extra_values` only for intentional one-off Helm overrides.

Networking intentionally matches Azure at the chart boundary: cloud load
balancers pass traffic to ingress-nginx, and Kubernetes Ingress TLS secrets own
TLS termination. ACM-specific load balancer TLS termination can still be layered
through `extra_values`, but is not the default shared path.

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
| `orchestration.deployment.artifact_prefix` | Artifact object-store prefix. |
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
| `orchestration.addons.install_secrets_store_csi_driver` | Install Secrets Store CSI driver. |
| `orchestration.addons.install_cert_manager` | Install cert-manager. |
| `orchestration.addons.install_flink_operator` | Install Flink operator. |
| `orchestration.addons.install_opentelemetry_operator` | Install OpenTelemetry operator. |
| `orchestration.prometheus.query_endpoint` | Prometheus query endpoint. |
| `orchestration.secrets.class_name` | SecretProviderClass name. |
| `orchestration.secrets.database_object_names.username` | Provider object name for DB username. |
| `orchestration.secrets.database_object_names.password` | Provider object name for DB password. |
| `orchestration.secrets.auth_object_names` | Provider object names for auth Secret keys. |
| `orchestration.secrets.extra_secret_objects` | Additional synced Kubernetes Secret objects. |
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
| `orchestration.extra_secret_objects` | Additional SecretProviderClass secret objects. |
| `orchestration.values` | Raw Helm values merged before extra values. |
| `orchestration.extra_values` | Additional raw Helm values. |
| `orchestration.extra_values_yaml` | Additional raw Helm values YAML strings. |

Supported AWS-specific fields:

| Field | Notes |
| --- | --- |
| `aws.region` | AWS region. Required. |
| `aws.database_secret_arn` | Secrets Manager ARN for DB credentials. Required. |
| `aws.warehouse_bucket` | S3 warehouse bucket name. Required. |
| `aws.orchestration_role_arn` | IAM role ARN for orchestration services. Required. |
| `aws.spark_compute_role_arn` | IAM role ARN for Spark compute. Required. |
| `aws.auth_secret_arn` | Secrets Manager ARN for auth secrets. Required when `orchestration.auth.enabled` is true. |
| `aws.flink_compute_role_arn` | IAM role ARN for Flink compute. Defaults to Spark role when omitted. |
| `aws.polaris_storage_role_arn` | IAM role ARN for Polaris storage access. |
| `aws.kv_table_prefix` | DynamoDB KV table prefix. |
| `aws.kv_enable_ttl` | Enable TTL on KV records. |
| `aws.kv_replica_regions` | DynamoDB KV replica regions. |
| `aws.eks_log_group` | EKS log group used by UI log links. |
| `aws.databricks_sp_secret_arn` | Secrets Manager ARN for Databricks service principal credentials. |

```hcl
orchestration = {
  install = {
    namespace    = "zipline-system"
    helm_wait    = true
    helm_timeout = 300
  }
  deployment = {
    customer_name   = "example"
    artifact_prefix = "s3://example-artifacts"
    zipline_version = "example-version"
  }
  database = {
    host = "example.postgres.amazonaws.com"
  }
  ingress = {
    domain = "zipline.example.com"
  }
}

aws = {
  region                 = "us-west-2"
  database_secret_arn    = "arn:aws:secretsmanager:us-west-2:123456789012:secret:zipline-db"
  warehouse_bucket       = "example-warehouse"
  orchestration_role_arn = "arn:aws:iam::123456789012:role/orchestration"
  spark_compute_role_arn = "arn:aws:iam::123456789012:role/spark-compute"
  flink_compute_role_arn = "arn:aws:iam::123456789012:role/flink-compute"
  polaris_storage_role_arn = "arn:aws:iam::123456789012:role/polaris-storage"
}
```

`flink_compute_role_arn` can be omitted when Flink should use the same service
account annotation as Spark.

Initialize this wrapper with a backend configured for the target environment:

```shell
aws eks update-kubeconfig --region us-west-2 --name example-eks

tofu init -reconfigure \
  -backend-config=bucket=example-opentofu-state \
  -backend-config=key=zipline-orchestration-state \
  -backend-config=region=us-west-2 \
  -backend-config=encrypt=true
```
