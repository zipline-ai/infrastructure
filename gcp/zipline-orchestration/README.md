# GCP Zipline Orchestration

Creates GCP infrastructure for Zipline, installs the shared
`charts/zipline-orchestration` chart on GKE, and connects cloud resources to
the shared `modules/zipline-orchestration` module.

The wrapper creates a regional GKE Standard cluster, Cloud SQL PostgreSQL,
Bigtable, GCS buckets, service accounts and IAM grants, Secret Manager secrets,
and a public ingress load balancer. It enables Google Managed Service for
Prometheus. DNS records are managed separately.

## Prerequisites

- An existing GCP project with billing and the APIs needed for GKE, Compute,
  Cloud SQL, Service Networking, Bigtable, Cloud Storage, Secret Manager, IAM,
  Monitoring, and BigQuery enabled. This wrapper does not enable project APIs.
- Credentials allowed to create these resources and manage their IAM policies,
  including grants on any existing buckets or secrets you reference.
- OpenTofu 1.9+, Google Cloud CLI (`gcloud`), `gke-gcloud-auth-plugin`, and
  `kubectl` on PATH. Apply uses `gcloud` and `kubectl` to configure monitoring.
- Available regional quota and machine types for the chosen node pools.

Authenticate the CLI and Application Default Credentials before deploying:

```shell
gcloud auth login
gcloud auth application-default login
gcloud components install gke-gcloud-auth-plugin
```

The machine running OpenTofu must be able to reach the GKE API endpoint,
including when you configure a private endpoint.

## Configuration Files

Create local, git-ignored `customer.auto.tfvars` and `backend.hcl` files in
`gcp/zipline-orchestration`. The root accepts two top-level objects:

- `orchestration`: shared Zipline installation settings.
- `gcp`: GCP infrastructure settings.

A starting configuration looks like this. Replace the project, domain, version,
and bucket names with your own values. GCS bucket names must be globally unique;
the artifact, warehouse, and logs buckets are created by this stack.

```hcl
orchestration = {
  deployment = {
    customer_name   = "example"
    artifact_prefix = "gs://example-zipline-artifacts"
    zipline_version = "<zipline-release-tag>"
  }
  ingress = {
    domain = "zipline.example.com"
  }
}

gcp = {
  project_id               = "example-project"
  region                   = "us-central1"
  warehouse_bucket         = "example-zipline-warehouse"
  logs_bucket              = "example-zipline-logs"
  spark_libs_bucket         = "example-zipline-spark-libs"
  create_spark_libs_bucket  = true
}
```

Alternatively, use `crucible.auto.tfvars.example` as a JSON configuration
reference. Replace its environment-specific values and remove unused OAuth
providers. Use one auto-loaded configuration file to avoid competing values.

### State backend

Create a GCS state bucket before initializing the stack. Use a bucket name you
own and a location appropriate for your deployment:

```shell
gcloud storage buckets create gs://example-zipline-tfstate \
  --project=example-project --location=us-central1 \
  --uniform-bucket-level-access
gcloud storage buckets update gs://example-zipline-tfstate --versioning
```

Set `backend.hcl` to that bucket and a prefix unique to this environment:

```hcl
bucket = "example-zipline-tfstate"
prefix = "zipline-orchestration/example"
```

Restrict access to state: it contains generated database credentials and the
GCS HMAC credentials used by Data Explorer.

### Optional shared configuration storage

If your organization uses the repository's configuration scripts, run these
from this wrapper directory:

```shell
../../pull_crucible_config.sh gcp
../../diff_crucible_config.sh gcp
../../push_crucible_config.sh gcp
```

Pull replaces local configuration; save local edits before using it. These
scripts require `jq`, use **GCS**, and default to bucket
`zipline-crucible-vars` and key
`gcp/zipline-orchestration/crucible.auto.tfvars.json`. Override
`CRUCIBLE_CONFIG_BUCKET`, `CRUCIBLE_CONFIG_KEY`, and `CRUCIBLE_CONFIG_ROOT`
for your organization. The config bucket must already exist. It is separate
from the state bucket; an AWS S3 bucket with the same name does not supply it.
The JSON tfvars must contain both `orchestration` and `gcp` objects.

## Required Inputs

| Field | Purpose |
| --- | --- |
| `orchestration.deployment.customer_name` | Prefix for generated resource names. Use a short name compatible with GCP resource naming rules. |
| `orchestration.deployment.artifact_prefix` | `gs://<bucket>` URI for artifacts; the wrapper creates the bucket portion. |
| `orchestration.deployment.zipline_version` | Release image tag for Zipline services. |
| `orchestration.ingress.domain` | Public hostname for the UI and service ingress routes. |
| `gcp.project_id` | Existing target GCP project. |
| `gcp.region` | Region for the cluster, database, and buckets. |
| `gcp.warehouse_bucket` | Bare GCS bucket name to create for warehouse data. |

## Optional Inputs

Add these fields inside the existing `orchestration` or `gcp` object.

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

Crucible always runs Spark 4. Spark jobs and the History Server use
`ziplineai/spark:nightly`, Flink uses `ziplineai/flink:1.20.3-spark4`, and Hub
and Eval use the Spark 4 variant of `orchestration.deployment.zipline_version`.
These images cannot be overridden through Terraform. Configure a pull secret
when the environment needs authenticated Docker Hub pulls.

| Field | Default | Use when |
| --- | --- | --- |
| `orchestration.image_pull_secret.name` | `docker-hub-creds` | A Kubernetes image pull Secret already exists, or you want a custom generated Secret name. |
| `orchestration.image_pull_secret.create` | `false` | Terraform should create the Docker Hub pull Secret. |
| `orchestration.image_pull_secret.dockerhub_username` | `ziplineai` | The pull token belongs to a different Docker Hub user. |
| `orchestration.image_pull_secret.dockerhub_token` | `""` | Required when `create = true`. |

Hub and Eval use the GCP repositories `ziplineai/hub-gcp` and
`ziplineai/eval-gcp`.

### Ingress and TLS

The wrapper reserves a regional external IP for ingress-nginx and creates a
public GKE L4 load balancer. After apply, create a DNS A record for
`orchestration.ingress.domain` pointing to `ingress_load_balancer_ip`.
TLS terminates at ingress-nginx using a Kubernetes TLS Secret.

For cert-manager HTTP-01 certificates, add these settings to `orchestration`.
DNS must resolve to the ingress IP and port 80 must be reachable for validation:

```hcl
ingress = {
  domain                      = "zipline.example.com"
  tls_secret_name             = "zipline-tls"
  cert_manager_cluster_issuer = "letsencrypt-prod"
  create_cluster_issuer       = true
  cluster_issuer_email        = "admin@example.com"
}
```

| Field | Default | Use |
| --- | --- | --- |
| `gcp.ingress_load_balancer_ip` | newly reserved IP | Use an existing regional external IP address. |
| `gcp.ingress_traffic_policy` | `Cluster` | Set `Local` when client IP preservation and ingress placement are configured accordingly. |
| `orchestration.ingress.class_name` | `nginx-ui` | Select a different ingress class. |
| `orchestration.ingress.annotations` | `{}` | Add application ingress annotations. |
| `orchestration.ingress.tls_secret_name` | `""` | Attach an existing or cert-manager-managed TLS Secret. |
| `orchestration.ingress.cert_manager_cluster_issuer` | `""` | Select a cert-manager ClusterIssuer. |
| `orchestration.ingress.create_cluster_issuer` | `false` | Create the selected ClusterIssuer. |
| `orchestration.ingress.cluster_issuer_email` | `""` | Set the ACME contact email. |
| `orchestration.ingress.cluster_issuer_server` | Let's Encrypt production | Select another ACME endpoint. |
| `orchestration.ingress.cluster_issuer_secret_name` | `""` | Customize the ACME account Secret name. |
| `orchestration.ingress.cluster_issuer_ingress_class` | ingress class name | Override the HTTP-01 solver ingress class. |

### Authentication and Secret Manager

Authentication defaults to disabled. To enable it, set
`orchestration.auth.enabled = true` and `gcp.auth_secret_id` to a bare Secret
Manager ID or `projects/<project>/secrets/<name>`. The shared
`orchestration.auth.secrets_arn` field is a fallback; on GCP its value is a
Secret Manager ID, despite the field name.

For a secret in the target project, Terraform creates the secret container but
**does not populate an auth secret version**. If the container already exists,
import it before apply. Supply its JSON value out of band before expecting the
authenticated application to become ready. A cross-project reference uses an
existing container. The deploying identity needs permission to grant access
there. The wrapper grants orchestration and External Secrets Operator access.

The JSON secret must have these properties (include empty values for unused
providers):

```json
{
  "auth-secret": "<random-session-secret>",
  "google-oauth-client-secret": "",
  "github-oauth-client-secret": "",
  "microsoft-entra-oauth-client-secret": "",
  "sso-client-secret": ""
}
```

Add `sso-saml-cert` when `orchestration.auth.sso_use_saml = true`. Store the
values in a protected local file and publish a version using your secret ID:

```shell
gcloud secrets versions add example-zipline-auth \
  --project=example-project --data-file=auth-secrets.json
```

Set the matching provider IDs and callback configuration in tfvars:

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
| `orchestration.compute.image_prepull_images` | Spark 4 image | You want to prepull additional images alongside the Spark 4 image. |
| `orchestration.compute.warm_pool` | enabled by the GCP wrapper | You need to tune pre-warmed Spark driver capacity. |
| `orchestration.compute.system_priority_class` | disabled | Compute support workloads need a PriorityClass. |

Use bare bucket names for storage inputs. The GCP wrapper supplies the compute
object store from `gcp.warehouse_bucket` and `gcp.region`. Spark uses Workload
Identity and Application Default Credentials, without service account key files.

### Network

Choose non-overlapping CIDRs that fit your network plan. Existing network inputs
are names, not self-links; this wrapper resolves them in `gcp.project_id`.

| Field | Default | Use |
| --- | --- | --- |
| `gcp.network` | `""` | Existing VPC name; set together with `subnet`, or omit both to create them. |
| `gcp.subnet` | `""` | Existing regional subnet name in the target project. It must have secondary ranges named `pods` and `services`, and Private Service Access configured for Cloud SQL. |
| `gcp.node_cidr` | `10.100.0.0/20` | Node range for a new subnet. |
| `gcp.pods_cidr` | `10.112.0.0/16` | Pod secondary range for a new subnet. |
| `gcp.services_cidr` | `10.128.0.0/20` | Service secondary range for a new subnet. |
| `gcp.enable_private_nodes` | `false` | Use private nodes; provision outbound connectivity as needed. This wrapper does not create Cloud NAT. |
| `gcp.enable_private_endpoint` | `false` | Restrict the control plane to private connectivity. |
| `gcp.master_ipv4_cidr_block` | `172.16.0.0/28` | Control-plane CIDR when private cluster settings are enabled. |
| `gcp.authorized_networks` | `[]` | API access CIDRs, e.g. `[{ cidr_block = "203.0.113.0/24", display_name = "office" }]`. Empty leaves authorized-network filtering unset. |

### GKE Capacity

Default compute pools use Arm machines. Choose Spark, Flink, and Ray images
that support their node architecture. Node pools use per-zone minimum and maximum
counts; regional totals can exceed the values shown below.

| Field | Default | Use |
| --- | --- | --- |
| `gcp.cluster_name` | `<customer_name>-gke` | Customize the cluster name. |
| `gcp.gke_release_channel` | `regular` | Select the GKE release channel. |
| `gcp.system_machine_type` | `n2-standard-16` | Machine type for system services. |
| `gcp.compute_machine_type` | `c4a-standard-8` | Machine type for Spark drivers, Flink, and Ray. |
| `gcp.executor_machine_type` | `c4a-standard-8-lssd` | Spark executor machine type with local SSDs. |
| `gcp.autoscaling_profile` | `OPTIMIZE_UTILIZATION` | Cluster autoscaling profile. |
| `gcp.storage_class` | `premium-rwo` | Storage class for StarRocks, history server, and Loki. |
| `gcp.personnel_emails` | `[]` | IAM members granted `roles/container.admin`, e.g. `["user:admin@example.com", "group:platform@example.com"]`. |
| `gcp.gke_deletion_protection` | `true` | Protect the cluster from deletion. |

| Pool | Capacity | Min / max per zone |
| --- | --- | --- |
| `system` | on-demand | 1 / 3 |
| `spark-driver` | on-demand | 1 / 10 |
| `spark-executor` | spot | 0 / 14 |
| `flink` | on-demand | 0 / 16 |
| `ray-control` | on-demand | 0 / 4 |
| `ray-worker` | on-demand | 0 / 8 |

`gcp.node_pools` is a map keyed by pool name. Each entry **replaces the whole
pool definition**, so copy the matching entry from [gke.tf](gke.tf) before
changing it. Include `machine_type`, `capacity_type`, `disk_size_gb`,
`min_count`, `max_count`, `initial_count`, `labels`, and `taints`; `disk_type`
is optional. Preserve the workload labels and taints used by job scheduling.

The GKE maintenance window is currently fixed to Saturday 08:00–12:00 UTC;
`gcp.maintenance_window` is declared but does not change it.

### Storage and IAM Grants

Orchestration, Spark, Flink, and Eval receive objectAdmin on the owned artifact,
warehouse, and logs buckets. Spark and Flink receive objectViewer on the jar
bucket. Polaris has a separate warehouse identity for credential vending.
Data Explorer uses a bucket-scoped identity and GCS HMAC credentials.

| Field | Default | Use |
| --- | --- | --- |
| `gcp.logs_bucket` | `zipline-logs-<customer_name>` | Name of the logs bucket to create. |
| `gcp.spark_libs_bucket` | `zipline-spark-libs` | Existing jar bucket when explicitly set; when omitted, the wrapper creates the default name. |
| `gcp.create_spark_libs_bucket` | `false` | Create an explicitly named jar bucket instead of attaching an existing one. |
| `gcp.flink_jars_base_path` | `gs://<spark_libs_bucket>/spark-4.1.3/libs/` | GCS prefix containing the Flink dependency jars. Upload the required jars separately; creating a bucket does not publish them. |
| `gcp.shared_warehouse_bucket` | `""` | Existing shared bucket: orchestration, Eval, and Spark receive objectViewer. |
| `gcp.additional_data_buckets` | `[]` | Existing buckets granting objectAdmin to Spark and objectViewer to orchestration and Eval. |
| `gcp.additional_flink_buckets` | `[]` | Existing buckets granting objectAdmin to Flink. |
| `gcp.additional_flink_readonly_buckets` | `[]` | Existing buckets granting objectViewer to Flink. |
| `gcp.bucket_force_destroy` | `false` | Allow deletion of non-empty managed buckets. This deletes their contents. |
| `gcp.cmek_key_id` | `""` | KMS key reference used by storage, Cloud SQL, Bigtable, and secrets; provision compatible keys and service-agent permissions before use. |

### Database

Cloud SQL uses private IP only. Credentials are written to Secret Manager as
JSON `username` and `password` fields and synchronized into Kubernetes through
External Secrets Operator.

| Field | Default | Use |
| --- | --- | --- |
| `gcp.database_name` | `execution_info` | PostgreSQL database name. |
| `gcp.database_username` | `locker_user` | Database user; password is generated automatically. |
| `gcp.database_version` | `POSTGRES_16` | PostgreSQL version. |
| `gcp.cloudsql_tier` | `db-custom-2-4096` | Instance CPU and memory tier. |
| `gcp.cloudsql_availability_type` | `REGIONAL` | Availability configuration. |
| `gcp.cloudsql_edition` | `ENTERPRISE` | Cloud SQL edition. |
| `gcp.cloudsql_disk_size` | `20` | Initial SSD size in GB. |
| `gcp.cloudsql_disk_autoresize_limit` | `100` | Autosize ceiling in GB; `0` means unlimited. |
| `gcp.cloudsql_max_connections` | `300` | PostgreSQL connection limit; changes can restart the instance. |
| `gcp.cloudsql_backup_retention_days` | `7` | Number of retained backups (the implementation uses COUNT, despite the input name). |
| `gcp.cloudsql_query_insights` | `false` | Enable Query Insights. |
| `gcp.database_deny_maintenance_start_date` | `2026-01-01` | Maintenance exclusion start; choose dates appropriate to your deployment. |
| `gcp.database_deny_maintenance_end_date` | `2026-01-14` | Maintenance exclusion end. |
| `gcp.database_deletion_protection` | `true` | Protect the database from Terraform deletion. |
| `gcp.database_create_final_backup` | `true` | Attempt an on-demand backup during destroy; backup failure does not block destroy. |

### Bigtable

The wrapper creates the `GROUPBY_INGEST` app profile and fixed-name KV and
metadata tables. Spark and Flink identities have `bigtable.user`, which does
not permit creating additional dataset-named tables; arrange that provisioning
or the required permissions before workloads that need those tables.

| Field | Default | Use |
| --- | --- | --- |
| `gcp.bigtable_instance` | `zipline-<customer_name>-instance` | Name of the instance to create; this is not an existing-instance attachment. |
| `gcp.bigtable_zone` | `<region>-a` | Zone for the SSD cluster; ensure it supports Bigtable. |
| `gcp.bigtable_min_nodes` | `1` | Autoscaling minimum. |
| `gcp.bigtable_max_nodes` | `10` | Autoscaling maximum. |
| `gcp.bigtable_cpu_target` | `60` | Autoscaling CPU target percentage. |
| `gcp.bigtable_storage_target_gib` | `2560` | Autoscaling storage target per node in GiB. |
| `gcp.bigtable_deletion_protection` | `true` | Protect the instance from deletion. |

### Additional Secrets

The wrapper configures a GCP Secret Manager ClusterSecretStore named
`zipline-secret-store`. Prefer `gcp.extra_external_secrets` for GCP declarations.
The same-project auth container has unconditional `prevent_destroy`; the
`gcp.secret_deletion_protection` input is declared but does not control it.

| Field | Default | Use |
| --- | --- | --- |
| `gcp.extra_secret_ids` | `[]` | Existing Secret Manager IDs requiring orchestration and ESO secretAccessor grants. |
| `gcp.extra_external_secrets` | `[]` | Additional ExternalSecret objects; IDs in `spec.data[].remoteRef.key` also receive access grants. |

### Observability

GKE managed Prometheus is enabled. The wrapper creates PodMonitoring resources
for Hub and, when deployed, Fetcher. The UI uses `METRICS_PROVIDER=gcp` and the
project-scoped Monitoring Prometheus endpoint. Hub uses the Prometheus metrics
reader on port `8905`; customize `orchestration.hub.chronon_metrics_reader` and
`orchestration.hub.metrics_port` only when the runtime supports the change.

`gcp.logging_components` and `gcp.monitoring_components` override the GKE
component lists in [locals.tf](locals.tf). Defaults include workload and system
logging, control-plane logs, and system/control-plane/workload monitoring.
Cloud Logging is selected through `LOG_PROVIDER=gcp`.

### Addons

The shared module installs common Kubernetes addons by default.

| Field | Default | Use when |
| --- | --- | --- |
| `orchestration.addons.install_external_secrets_operator` | `true` | External Secrets Operator is installed elsewhere. |
| `orchestration.addons.install_cert_manager` | `true` | cert-manager is installed elsewhere or not needed. |
| `orchestration.addons.install_flink_operator` | `true` | Flink operator is installed elsewhere or not needed. |
| `orchestration.addons.install_opentelemetry_operator` | `false` | OpenTelemetry operator should be installed. |
| `orchestration.addons.install_metrics_server` | `false` | Metrics Server is not already installed in the cluster and should be managed by this wrapper. |
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

## Deploy

From `gcp/zipline-orchestration`, initialize the backend and review the plan:

```shell
tofu init -reconfigure -backend-config=backend.hcl
tofu validate
tofu plan -out=customer.tfplan
tofu apply customer.tfplan
```

If auth is enabled, ensure the auth secret has a populated version as described
above. After apply, configure DNS using the ingress IP and configure kubectl:

```shell
tofu output -raw ingress_load_balancer_ip
tofu output -raw kubeconfig_command
# Run the command printed above, then inspect the installation:
kubectl get pods -n zipline-system
kubectl get ingress -n zipline-system
```

Use your configured namespace if it differs from `zipline-system`. Verify DNS,
TLS issuance, and application readiness before submitting jobs.

## Outputs

| Output | Use |
| --- | --- |
| `network`, `subnet`, `network_created` | Inspect the network used by the stack. |
| `gke_cluster_name`, `gke_cluster_endpoint` | Inspect the cluster; endpoint output is sensitive. |
| `kubeconfig_command` | Command to configure kubectl for the cluster. |
| `ingress_load_balancer_ip`, `ingress_load_balancer_target` | Configure external DNS. |
| `cloudsql_connection_name`, `cloudsql_private_ip` | Inspect the private PostgreSQL instance. |
| `db_credentials_secret_id` | Locate generated credentials in Secret Manager. |
| `warehouse_bucket`, `artifact_bucket`, `logs_bucket`, `spark_libs_bucket` | Inspect storage names. |
| `bigtable_instance` | Inspect the Bigtable instance. |
| `orchestration_gsa_email`, `spark_gsa_email`, `flink_gsa_email`, `polaris_gsa_email` | Inspect workload identities and integrate external access grants. |

## Workload Prerequisites

Infrastructure installation alone does not establish workload support. Confirm
with your Zipline release that the GCP runtime and job submission support are
available before running batch jobs. Default Arm pools require matching image
manifests. Streaming additionally requires the GCP Flink dependency jars in
`gcp.flink_jars_base_path`, a Flink image with the GCS connector, and runtime
support for the GCP jar set. Ray training requires history collector wiring.

## Notes

The shared chart bootstraps Polaris runtime authentication and writes the
`OC_CREDENTIAL` value into the `polaris-client-credentials` Kubernetes Secret.
The GCP wrapper configures a GCS catalog location under the warehouse bucket.

GKE, Cloud SQL, and Bigtable deletion protection default to enabled. Disable
and apply the corresponding protection settings before an intentional destroy.
Auth secret destruction remains blocked by its Terraform lifecycle rule.
Destroy also uses `gcloud` and `kubectl` to drain controller-managed resources.

`gcp.artifact_repository`, `gcp.compute_namespace_prefix`, and
`gcp.cloudflare_record_name` currently do not configure registry grants,
namespace creation, or DNS records. Use the documented image, compute namespace,
and external DNS configuration instead.

## Conf repository sandbox

Set `orchestration.conf_repo.url` to enable the repository editor and sandbox.
See the [sandbox configuration guide](../../charts/zipline-orchestration/SANDBOX.md)
for inputs, cloud secret references, and image availability requirements.
