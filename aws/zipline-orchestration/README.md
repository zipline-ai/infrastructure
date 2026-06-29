# AWS Zipline Orchestration

Creates the AWS cloud primitives for Zipline orchestration, installs the shared
`charts/zipline-orchestration` chart on EKS, and wires AWS infrastructure into
cloud-neutral chart values.

AWS-specific work stays at this layer:

- EKS, the EBS CSI driver, AWS Load Balancer Controller, and AWS Secrets Store
  CSI provider.
- RDS Postgres and Secrets Manager credentials projected through the generic
  chart `database` and `secrets` values.
- IAM roles and service-account annotations for orchestration and compute pods.
- DynamoDB metadata tables, Glue registry, AMP workspace, and Polaris storage
  vending role.
- NLB annotations on the shared ingress-nginx controller Services.

The wrapper owns AWS-specific resources and exposes only generic deployment
context to `modules/zipline-orchestration`: database connection details,
object-store location, Kubernetes service-account annotations, secret provider
objects, metrics endpoint, and ingress service settings. Azure should implement
the same contract with AKS, Azure Postgres, Key Vault, Azure storage, and
workload identity rather than adding cloud-specific behavior to the chart.
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
| `orchestration.database.host` | Postgres host when the cloud wrapper does not provide one. |
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
| `aws.warehouse_bucket` | S3 warehouse bucket name. Required. |
| `aws.vpc_id` | VPC for EKS and RDS. Required. |
| `aws.primary_subnet_id` | Primary subnet for EKS, RDS, and AMP scraper. Required. |
| `aws.secondary_subnet_id` | Secondary subnet for EKS, RDS, and AMP scraper. Required. |
| `aws.cluster_name` | Optional EKS cluster name. Defaults to `<customer_name>-eks`. |
| `aws.eks_version` | EKS Kubernetes version. |
| `aws.eks_instance_type` | EKS node instance type. |
| `aws.eks_min_size` / `aws.eks_desired_size` / `aws.eks_max_size` | Default node-group sizing. |
| `aws.eks_disk_size` | Default node root volume size in GB. |
| `aws.personnel_arns` | IAM principals granted EKS cluster-admin access. |
| `aws.auth_secret_arn` | Existing Secrets Manager ARN for auth secrets. Required when auth is enabled unless `aws.auth_secret_values` is supplied. |
| `aws.auth_secret_values` | Secret values used to create the auth Secrets Manager secret. |
| `aws.extra_secret_provider_objects` | Additional AWS Secrets Store CSI provider objects for externally managed secrets. |
| `aws.kv_table_prefix` | DynamoDB KV table prefix. |
| `aws.kv_enable_ttl` | Enable TTL on KV records. |
| `aws.kv_replica_regions` | DynamoDB KV replica regions. |
| `aws.kv_read_capacity` / `aws.kv_write_capacity` | Provisioned capacity for the table-partitions table. |
| `aws.eks_log_group` | EKS log group used by UI log links. |
| `aws.additional_data_buckets` | Extra buckets granted to Spark compute and orchestration read paths. |
| `aws.additional_flink_s3_buckets` | Extra buckets granted to Flink compute. |
| `aws.glue_schema_registry_name` | Existing Glue registry name. Defaults to creating `zipline-<customer_name>`. |
| `aws.msk_cluster_arn` | Optional MSK cluster ARN for Flink IAM permissions. |
| `aws.encryption_kms_key_arn` | Optional KMS key used by RDS, Secrets Manager, DynamoDB, and Polaris storage policy. |
| `aws.encryption_kms_key_arns` | Optional region-to-KMS-key map for DynamoDB replicas. |
DNS records are intentionally not managed by this wrapper. The wrapper outputs
`ingress_load_balancer_target`, which environment-specific DNS automation can
route through the DNS provider selected by that environment.

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
  image_pull_secret = {
    create          = true
    dockerhub_token = "..."
  }
  ingress = {
    domain = "zipline.example.com"
  }
}

aws = {
  region              = "us-west-2"
  warehouse_bucket    = "example-warehouse"
  vpc_id              = "vpc-..."
  primary_subnet_id   = "subnet-..."
  secondary_subnet_id = "subnet-..."

  auth_secret_values = {
    google_oauth_client_secret = "..."
    github_oauth_client_secret = "..."
    sso_client_secret          = "..."
  }
}
```

Initialize this wrapper with a backend configured for the target environment:

```shell
tofu init -reconfigure \
  -backend-config=bucket=example-opentofu-state \
  -backend-config=key=zipline-orchestration-state \
  -backend-config=region=us-west-2 \
  -backend-config=encrypt=true
```
