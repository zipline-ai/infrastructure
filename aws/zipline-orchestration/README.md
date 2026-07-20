# AWS Zipline Orchestration

Creates the AWS cloud primitives for Zipline orchestration, installs the shared
`charts/zipline-orchestration` chart on EKS, and wires AWS infrastructure into
cloud-neutral chart values.

This wrapper owns AWS resources such as EKS, Karpenter, RDS Postgres, Secrets
Manager, S3 buckets, IAM roles, DynamoDB tables, Glue, AWS Managed Prometheus,
and the AWS load balancer integrations for ingress-nginx. The shared
`modules/zipline-orchestration` module owns the common Helm values and chart
installation behavior.

DNS records are intentionally not managed here. After apply, use the
`ingress_load_balancer_target` output in the DNS automation for the target
environment.

## Configuration Files

Supply environment-specific values through local, git-ignored Terraform variable
files. The root accepts two top-level objects:

- `orchestration`: shared Zipline installation settings.
- `aws`: AWS-specific infrastructure settings.

A minimal starting point looks like this:

```hcl
orchestration = {
  deployment = {
    customer_name   = "example"
    artifact_prefix = "s3://example-artifacts"
    zipline_version = "example-version"
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
}
```

Run with a backend configured for the target environment:

```shell
../../pull_crucible_config.sh aws
tofu init -reconfigure -backend-config=backend.hcl
```

## Required Inputs

Set these for every environment.

| Field | Why it is required |
| --- | --- |
| `orchestration.deployment.customer_name` | Used as the environment/customer prefix for generated resources. |
| `orchestration.deployment.artifact_prefix` | S3 URI for Zipline artifacts. The wrapper creates the bucket portion of this URI. |
| `orchestration.deployment.zipline_version` | Image tag used across Zipline services. |
| `orchestration.ingress.domain` | Public host used by the UI, Hub, Eval, and supporting ingress routes. |
| `aws.region` | AWS region for all regional resources and providers. |
| `aws.warehouse_bucket` | S3 bucket for the warehouse. The wrapper creates this bucket. |
| `aws.vpc_id` | VPC for EKS and RDS. |
| `aws.primary_subnet_id` | First subnet for EKS, RDS, AWS Managed Prometheus scraping, and load balancer placement. |
| `aws.secondary_subnet_id` | Second subnet for EKS, RDS, AWS Managed Prometheus scraping, and load balancer placement. |

The two subnets should be suitable for the cluster and database placement in the
target VPC. The ingress-nginx NLB is annotated to use these same subnets.

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
| `orchestration.hub.image` | AWS wrapper default | You need to override the AWS Hub image. |
| `orchestration.eval.image` | AWS wrapper default | You need to override the AWS Eval image. |

### Ingress and TLS

By default, the wrapper creates an internet-facing NLB for ingress-nginx and the
shared chart creates Kubernetes Ingress resources for `orchestration.ingress.domain`.
TLS termination is expected to happen at ingress-nginx through Kubernetes TLS
Secrets.

| Field | Default | Use when |
| --- | --- | --- |
| `orchestration.ingress.class_name` | `nginx-ui` | You use a different ingress class. |
| `orchestration.ingress.tls_secret_name` | `""` | A Kubernetes TLS Secret should be attached to app ingresses. |
| `orchestration.ingress.cert_manager_cluster_issuer` | `""` | cert-manager should issue TLS certificates for the app ingresses. |
| `orchestration.ingress.create_cluster_issuer` | `false` | The chart should create a cert-manager ClusterIssuer. |
| `orchestration.ingress.cluster_issuer_email` | `""` | Required by ACME when creating a ClusterIssuer. |
| `orchestration.ingress.cluster_issuer_server` | Let's Encrypt production | You need staging ACME or another ACME server. |
| `orchestration.ingress.cluster_issuer_secret_name` | `""` | You want a specific ACME account private-key Secret name. |
| `orchestration.ingress.cluster_issuer_ingress_class` | ingress class name | The HTTP-01 solver should use a different ingress class. |
| `orchestration.ingress.annotations` | `{}` | App ingresses need extra annotations. |

ACM-specific load balancer TLS termination is not the default shared path. If an
environment needs it, layer the required ingress-nginx service annotations
through Helm values.

### Authentication

Authentication is disabled unless `orchestration.auth.enabled = true`. When auth
is enabled, the AWS wrapper must be able to provide the auth secret values from
Secrets Manager.

Choose one of these secret sources:

| Field | Use when |
| --- | --- |
| `aws.auth_secret_arn` | Auth secrets already exist in AWS Secrets Manager. |
| `orchestration.auth.secrets_arn` | You want to use the shared auth secret ARN field instead of the AWS-specific alias. |
| `aws.auth_secret_values` | Terraform should create the AWS Secrets Manager secret from supplied values. |

The expected auth secret properties are:

- `auth-secret`
- `google-oauth-client-secret`
- `github-oauth-client-secret`
- `microsoft-entra-oauth-client-secret`
- `sso-client-secret`
- `sso-saml-cert`, only when `orchestration.auth.sso_use_saml = true`

When using `aws.auth_secret_values`, provide the same values with Terraform-safe
map keys:

```hcl
aws = {
  auth_secret_values = {
    auth_secret                         = "..."
    google_oauth_client_secret          = "..."
    github_oauth_client_secret          = "..."
    microsoft_entra_oauth_client_secret = "..."
    sso_client_secret                   = "..."
    sso_saml_cert                       = "..."
  }
}
```

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
| `orchestration.compute.warm_pool` | disabled in shared defaults, enabled by AWS provider values | You need to tune pre-warmed Spark driver capacity. |
| `orchestration.compute.system_priority_class` | disabled | Compute support workloads need a PriorityClass. |

Do not set `orchestration.compute.object_store.bucket` to an S3 URI. The AWS
wrapper supplies the warehouse bucket and region from `aws.warehouse_bucket` and
`aws.region`.

### Karpenter and EKS Capacity

Karpenter is enabled by default. The wrapper creates a tainted `system` NodePool
for Zipline system services and tainted compute NodePools for Spark drivers,
Spark executors, Flink job managers, and Flink task managers.

| Field | Default | Use when |
| --- | --- | --- |
| `aws.cluster_name` | `<customer_name>-eks` | You need a stable or pre-approved EKS cluster name. |
| `aws.eks_version` | `1.36` | The environment must pin a different Kubernetes version. |
| `aws.eks_instance_type` | `m8a.4xlarge` | The managed default node group needs a different instance type. |
| `aws.eks_min_size` | `3` | The default node group minimum should change. |
| `aws.eks_desired_size` | `3` | The default node group desired size should change. |
| `aws.eks_max_size` | `8` | The default node group maximum should change. |
| `aws.eks_disk_size` | `100` | EKS node root volumes need a different size in GB. |
| `aws.personnel_arns` | `[]` | Human or automation IAM principals need EKS cluster-admin access. |
| `aws.karpenter.enabled` | `true` | Karpenter should be disabled for an environment. |
| `aws.karpenter.namespace` | `kube-system` | Karpenter should run in a different namespace. |
| `aws.karpenter.release_name` | `karpenter` | The Karpenter Helm release needs a different name. |
| `aws.karpenter.version` | `1.13.0` | The Karpenter chart version needs to be pinned differently. |
| `aws.karpenter.enable_zonal_shift` | `false` | You want Karpenter zonal shift integration. |
| `aws.karpenter.values` | `{}` | The Karpenter controller Helm release needs extra values. |
| `aws.karpenter.ec2_node_class` | computed secure defaults | You need to override EC2NodeClass details such as AMI alias, selectors, tags, or user data. |
| `aws.karpenter.ec2_node_class.instance_store_policy` | `RAID0` | You need to override how Karpenter configures EC2 instance-store disks. |
| `aws.karpenter.node_pools` | generated pools | You need to override generated NodePools or add new ones. |

Common Karpenter sizing knobs:

| Field | Default | Use when |
| --- | --- | --- |
| `aws.karpenter.driver_arch` | `["arm64"]` | Driver nodes must use another architecture. |
| `aws.karpenter.driver_categories` | `["m"]` | Driver nodes need other EC2 instance families. |
| `aws.karpenter.executor_arch` | `["arm64"]` | Executor nodes must use another architecture. |
| `aws.karpenter.executor_categories` | `["c", "m", "r"]` | Executor nodes need other EC2 instance families. |
| `aws.karpenter.executor_capacity_type` | `["spot"]` | Executors should run on on-demand, spot, or both. |
| `aws.karpenter.executor_min_categories` | `2` | Spot diversification requirements need tuning. |
| `aws.karpenter.min_instance_generation` | `"6"` | Pools should allow older or require newer instance generations. |
| `aws.karpenter.pool_limits` | `{ cpu = "1000", memory = "4000Gi" }` | You want a global pool launch cap. |
| `aws.karpenter.driver_limits` | `{ cpu = "100", memory = "400Gi" }` | Driver pools need a different launch cap. |
| `aws.karpenter.executor_limits` | `{ cpu = "1000", memory = "4000Gi" }` | Executor pools need a different launch cap. |
| `aws.karpenter.system_expire_after` | `Never` | System nodes should be periodically recycled. |
| `aws.karpenter.compute_expire_after` | `720h` | Compute nodes should recycle more or less often. |
| `aws.karpenter.system_termination_grace_period` | `5m` | System nodes need a different drain grace period. |

Spark executor pools require EC2 instance types with local NVMe. Karpenter
combines all instance-store disks into RAID0 and exposes the result as standard
Kubernetes ephemeral storage, so Spark can use its default `emptyDir` local
directories without provider-specific mounts or node labels.

### Storage, Logs, and IAM Grants

The wrapper creates the artifact bucket, warehouse bucket, and logs bucket. Other
bucket fields grant access to externally managed buckets and do not create those
buckets.

| Field | Default | Use when |
| --- | --- | --- |
| `aws.logs_bucket` | `zipline-logs-<customer_name>` | You need a specific logs bucket name. |
| `aws.shared_warehouse_bucket` | `""` | Orchestration services need read access to an existing shared warehouse bucket. |
| `aws.spark_libs_bucket` | `""` | Spark needs access to an existing bucket for shared libraries. |
| `aws.additional_data_buckets` | `[]` | Spark compute and orchestration read paths need access to more buckets. |
| `aws.additional_flink_s3_buckets` | `[]` | Flink compute needs access to more buckets. |
| `aws.encryption_kms_key_arn` | `""` | RDS, Secrets Manager, DynamoDB, or Polaris storage policy should use a specific KMS key. |
| `aws.encryption_kms_key_arns` | `{}` | DynamoDB replica regions need region-specific KMS keys. |

### Database

The AWS wrapper creates RDS Postgres and supplies the shared chart database
connection values. Override these only when the default RDS shape is not right
for the environment.

| Field | Default | Use when |
| --- | --- | --- |
| `aws.database_name` | `execution_info` | Zipline should use a different database name. |
| `aws.database_username` | `locker_user` | Zipline should use a different database username. |
| `aws.database_instance_class` | `db.t3.medium` | RDS needs more or less capacity. |
| `aws.database_allocated_storage` | `20` | RDS needs a different initial storage size in GB. |
| `aws.database_multi_az` | `true` | You want to disable or explicitly set Multi-AZ. |
| `aws.database_publicly_accessible` | `false` | The RDS instance must be publicly accessible. |
| `aws.database_backup_retention_days` | `7` | Backups need a different retention period. |

### DynamoDB, Glue, MSK, and Observability

| Field | Default | Use when |
| --- | --- | --- |
| `aws.kv_table_prefix` | `""` | Hub needs a prefix for Chronon KV tables. |
| `aws.kv_enable_ttl` | `true` | TTL should be disabled for KV records. |
| `aws.kv_replica_regions` | `[]` | DynamoDB global table replicas are required. |
| `aws.kv_read_capacity` | `10` | Provisioned read capacity for the table-partitions table needs tuning. |
| `aws.kv_write_capacity` | `10` | Provisioned write capacity for the table-partitions table needs tuning. |
| `aws.glue_schema_registry_name` | `zipline-<customer_name>` | You want to use an existing Glue registry or a specific registry name. |
| `aws.msk_cluster_arn` | `""` | Flink needs IAM permissions for an MSK cluster. |
| `aws.amp_workspace_arn` | created workspace ARN | Scraping, UI queries, and IAM permissions should use an existing AWS Managed Prometheus workspace. |
| `aws.eks_log_group` | `/aws/eks/<cluster_name>/containers` | UI log links should point at a different EKS log group. |

### Secrets

The wrapper configures External Secrets Operator against AWS Secrets Manager for
database and auth secrets. Add extra secrets when workloads need additional
Kubernetes Secrets sourced from AWS Secrets Manager.

| Field | Use when |
| --- | --- |
| `aws.extra_external_secrets` | You need additional `ExternalSecret` resources. |
| `aws.extra_secret_arns` | The External Secrets service account needs access to more Secrets Manager ARNs. |
| `orchestration.secrets.extra_external_secrets` | You want to define additional ExternalSecret resources through the shared interface. |
| `orchestration.secrets.secret_store` | You need to customize the generated SecretStore. |
| `orchestration.secrets.external_secrets_enabled` | External Secrets Operator is managed differently or disabled. |

Legacy SecretProviderClass inputs are no longer supported. Use External Secrets
fields instead.

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
| `orchestration.eval_env` | Eval needs extra environment variables. |
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
| `kubectl_config_command` | Configure `kubectl` for the created EKS cluster. |
| `artifact_bucket` | Confirm the artifact bucket created from `artifact_prefix`. |
| `warehouse_bucket` | Confirm the warehouse bucket. |
| `logs_bucket` | Confirm the logs bucket. |
| `ingress_load_balancer_target` | Create the external DNS record for `orchestration.ingress.domain`. |
| `orchestration_service_account_role_arn` | Inspect or integrate the orchestration IRSA role. |
| `spark_compute_role_arn` | Inspect or integrate the Spark compute IRSA role. |
| `flink_compute_role_arn` | Inspect or integrate the Flink compute IRSA role. |

## Notes

The shared Helm chart bootstraps Polaris runtime authentication. On each install
or upgrade, the Polaris bootstrap hook reconciles a non-root `chronon`
principal, grants it access to the seeded catalog role, writes its
`client_id:client_secret` value into the `polaris-client-credentials`
Kubernetes Secret as `OC_CREDENTIAL`, and restarts Hub so Spark catalog
placeholders can be resolved without customer-supplied Polaris credentials.
