# GCP Zipline Orchestration

Creates GCP infrastructure for Zipline, installs the shared
`charts/zipline-orchestration` chart on GKE, and connects cloud resources to
the shared `modules/zipline-orchestration` module.

The wrapper creates a regional GKE Standard cluster, Cloud SQL PostgreSQL,
Bigtable, GCS buckets, service accounts and IAM grants, Secret Manager secrets,
and a public ingress load balancer. It enables Google Managed Service for
Prometheus. DNS records are managed separately.

## Prerequisites

- An existing GCP project with billing. The wrapper enables the APIs listed in
  [apis.tf](apis.tf) and leaves them enabled at teardown. If your deploying
  identity cannot manage APIs, set `gcp.enable_apis = false` and have your
  platform team enable them before applying.
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

**Use this minimal example only in an isolated evaluation environment with
external network access restricted.** It leaves authentication disabled and
configures no TLS certificate, while the wrapper creates a public load
balancer. Before public deployment, enable authentication and populate its
Secret Manager values as described in [Authentication and Secret Manager](#authentication-and-secret-manager),
and configure a TLS certificate as described in [Ingress and TLS](#ingress-and-tls).
Verify both authentication and HTTPS before allowing public access.

```hcl
orchestration = {
  deployment = {
    customer_name   = "example"
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

`orchestration.deployment.artifact_prefix` is optional and defaults to
`gs://zipline-<customer_name>-artifacts` (`gs://zipline-example-artifacts` for
this example). Set it only to override the default artifact location.

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

## Required Inputs

| Field | Purpose |
| --- | --- |
| `orchestration.deployment.customer_name` | Prefix for generated resource names. Use a short name compatible with GCP resource naming rules. |
| `orchestration.deployment.zipline_version` | Release image tag for Zipline services. |
| `orchestration.ingress.domain` | Public hostname for the UI and service ingress routes. |
| `gcp.project_id` | Existing target GCP project. |
| `gcp.region` | Region for the cluster, database, and buckets. |

## Optional Inputs

Add these fields inside the existing `orchestration` or `gcp` object.

| Field | Default | Use |
| --- | --- | --- |
| `orchestration.deployment.artifact_prefix` | `gs://zipline-<customer_name>-artifacts` | Set only to override the default artifact URI; the wrapper creates the bucket portion. |
| `gcp.warehouse_bucket` | `zipline-<customer_name>-warehouse` | Bare warehouse bucket name to create. |
| `gcp.enable_apis` | `true` | Set to `false` when project APIs are managed externally. |

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
Configure a pull secret when the environment needs authenticated Docker Hub
pulls.

| Field | Default | Use when |
| --- | --- | --- |
| `orchestration.image_pull_secret.name` | `docker-hub-creds` | A Kubernetes image pull Secret already exists, or you want a custom generated Secret name. |
| `orchestration.image_pull_secret.create` | `false` | Terraform should create the Docker Hub pull Secret. |
| `orchestration.image_pull_secret.dockerhub_username` | `ziplineai` | The pull token belongs to a different Docker Hub user. |
| `orchestration.image_pull_secret.dockerhub_token` | `""` | Required when `create = true`. |

Hub and Eval use the GCP repositories `ziplineai/hub-gcp` and
`ziplineai/eval-gcp`.

### Container images

Override workload and helper images in your `.tfvars` file using the
[shared image settings](../../modules/zipline-orchestration/README.md#override-workload-images).

### Ingress and TLS

The wrapper reserves a regional external IP for ingress-nginx and creates a
public GKE L4 load balancer. Before creating DNS records, confirm the ingress
controller Service has an external IP in `.status.loadBalancer.ingress`, run
`tofu apply -refresh-only`, and reread `tofu output -raw ingress_dns_instructions`
as shown in [Deploy](#deploy). Create a DNS A record for
`orchestration.ingress.domain` pointing to the confirmed Service IP.

Until the Service publishes its IP and state is refreshed, the output can fall
back to the wrapper's reserved IP. That IP may be incorrect when
`orchestration.install.helm_wait = false` or a Helm override sets a different
`loadBalancerIP`. TLS terminates at ingress-nginx using a Kubernetes TLS Secret.

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

#### Use a client-managed TLS certificate

Configure your certificate management system to create and renew a Secret of
type `kubernetes.io/tls` in the Zipline installation namespace
(`orchestration.install.namespace`, which defaults to `zipline-system`). The
Secret must contain `tls.crt` and `tls.key`. The certificate must cover your
ingress hostname.

Merge these settings into your existing `orchestration` input:

```hcl
addons = {
  install_cert_manager = false
}

ingress = {
  domain                      = "zipline.customer.example"
  tls_secret_name             = "customer-zipline-tls"
  cert_manager_cluster_issuer = ""
  create_cluster_issuer       = false
}
```

Use your DNS hostname and Secret name. Remove any cert-manager issuer
annotations you previously set in `orchestration.ingress.annotations`.

For an existing deployment, create the client-managed Secret under a new name
that no cert-manager Certificate references. Set `tls_secret_name` to that new
name and apply the ingress changes with the bundled cert-manager still enabled.
Then verify that the HTTPS endpoint serves the client-managed certificate.
Before applying `install_cert_manager = false`, review the Terraform plan
and inventory cert-manager resources across the cluster. The bundled
`v1.13.3` chart defaults to `installCRDs = true`. Uninstalling it can delete
its CRDs and their custom resources across all namespaces, even if the plan
shows only the Helm release removal.

If those resources must remain, upgrade the bundled release first to a
supported chart version that retains CRDs on uninstall and verify that CRD
retention is enabled. The behavior was introduced in v1.15.0, and upgrading
the bundled release requires updating the add-on module's chart version.
If you cannot upgrade, back up the cert-manager resources before applying
and plan to restore any needed resources after reinstalling their CRDs.
[cert-manager Helm uninstall guidance](https://cert-manager.io/docs/installation/helm/#uninstalling)

If you enabled the optional OpenTelemetry Operator, verify how its webhook
certificate is provisioned before removing cert-manager.

#### Use an existing cert-manager ClusterIssuer

If you already run cert-manager in the cluster, you can let it issue and renew
the certificate. Set `cert_manager_cluster_issuer` to the existing issuer's
name, set `tls_secret_name` to the Secret cert-manager should populate, and set
`install_cert_manager` and `create_cluster_issuer` to `false`.

If Zipline originally created the ClusterIssuer, Helm removes it when
`create_cluster_issuer` becomes `false`. Before disabling creation, complete an
ownership handoff that preserves the issuer outside the Zipline Helm release,
or create an independently managed ClusterIssuer under a different name and
verify that it is Ready. If you use a replacement, update
`cert_manager_cluster_issuer` and migrate any other Certificates that reference
the old issuer before retiring it. Keep a working cert-manager controller and
its CRDs in place, and verify that affected certificates can still issue and
renew through the retained or replacement issuer.

Cert-manager creates and renews the Secret in this mode. Use a Secret name
reserved for cert-manager so each TLS Secret has a single writer. When switching
from a client-managed certificate, choose a different Secret name for the
issuer-managed certificate.

### Authentication and Secret Manager

Authentication defaults to disabled. To enable it, set
`orchestration.auth.enabled = true` and `gcp.auth_secret_id` to a **bare secret
ID in the same project as the cluster** (`gcp.project_id`), for example
`example-zipline-auth`. The shared `orchestration.auth.secrets_arn` field is a
fallback; on GCP it must also contain a bare, same-project secret ID, despite
the field name. Do not use a fully qualified resource path for either field.

Cross-project auth secrets are not supported: the generated Secret Manager
store is fixed to `gcp.project_id`, and the auth reference is passed through
without normalization. Cross-project auth requires a separate store that the
wrapper does not currently configure.


Create the auth secret and populate its JSON value before the full apply.
Terraform does not create the auth container or write its value; it grants
orchestration and External Secrets Operator access to the existing secret.
Helm waits for readiness by default, so applying without a populated secret
can time out waiting for authenticated services.

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
values in `$HOME/.config/zipline-bootstrap/auth-secrets.json`, outside the
repository. Create the private directory and file before editing the JSON:

```shell
umask 077
mkdir -p "$HOME/.config/zipline-bootstrap"
chmod 700 "$HOME/.config/zipline-bootstrap"
touch "$HOME/.config/zipline-bootstrap/auth-secrets.json"
chmod 600 "$HOME/.config/zipline-bootstrap/auth-secrets.json"
```

Keep this directory outside any Git checkout. Before creating the auth secret,
enable the Secret Manager API in the cluster project. The stack normally enables
it during apply, but this secret must exist first. If API enablement is managed
by your platform team, have them complete this step:

```shell
gcloud services enable secretmanager.googleapis.com --project=example-project
```

After editing the JSON, create and populate a new secret in the same cluster
project before applying the stack:

```shell
gcloud secrets create example-zipline-auth \
  --project=example-project --replication-policy=automatic \
  --data-file="$HOME/.config/zipline-bootstrap/auth-secrets.json"
```

If the secret already exists, publish a new version when needed:

```shell
gcloud secrets versions add example-zipline-auth \
  --project=example-project \
  --data-file="$HOME/.config/zipline-bootstrap/auth-secrets.json"
```

Use the bare ID `example-zipline-auth` in tfvars. The auth container is managed
externally.

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

The Hub creates team compute namespaces dynamically when teams sync. You do
not need to set `orchestration.compute.namespaces` or list each team in tfvars.
The default compute namespace is `zipline-default` for team `default`.

Use `orchestration.compute.namespace_defaults` to customize the namespace
policies used by the Hub's template. Set `orchestration.compute.namespaces` only
when you need additional namespaces provisioned by Helm or explicit per-namespace
settings. See the [team namespace guide](../../charts/zipline-orchestration/README.md#team-compute-namespaces)
for provisioning and permissions.

| Field | Default | Use when |
| --- | --- | --- |
| `orchestration.compute.default_namespace` | `zipline-default` | Jobs should default to another namespace. |
| `orchestration.compute.namespaces` | `[{ name = "zipline-default", team = "default" }]` | Optional: provision explicit namespaces through Helm; not required for dynamically created team namespaces. |
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
| `gcp.spark_libs_bucket` | `zipline-<customer_name>-spark-libs` | Existing jar bucket when explicitly set; when omitted, the wrapper creates the default name. |
| `gcp.create_spark_libs_bucket` | `false` | Create an explicitly named jar bucket instead of attaching an existing one. |
| `gcp.flink_jars_base_path` | Derived from jar bucket or artifact prefix | Override the Flink dependency jar prefix; see Workload Prerequisites below. Creating a bucket does not publish jars. |
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
Auth containers are managed externally and survive Terraform teardown.
`gcp.secret_deletion_protection` is declared but does not control them.

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
| `orchestration.addons.external_secrets_operator_values` | GCP Workload Identity annotation | Customize ESO Helm values; the wrapper preserves the required identity annotation. |
| `orchestration.addons.cert_manager_values` | `{}` | The cert-manager Helm release needs custom values. |

Custom `orchestration.addons.external_secrets_operator_values` preserve the
wrapper's required `iam.gke.io/gcp-service-account` annotation, including when
set to `{}`. Other service account annotations and operator values are retained.
The required annotation always points to
`<customer_name>-eso@<project_id>.iam.gserviceaccount.com`.

The wrapper resolves the ESO account name using the chart's rules: an explicit
`serviceAccount.name` takes precedence, otherwise the chart derives the name
from `fullnameOverride` or the release name and `nameOverride`, truncating to
63 characters and removing a trailing hyphen. With `serviceAccount.create = false`
and no explicit name, the operator uses `default`.

When the wrapper installs ESO and Helm does not create `external-secrets`,
the wrapper creates a separate annotated `external-secrets` account in the
installation namespace.
The ClusterSecretStore's fixed Workload Identity binding continues to use that
account; the ESO Deployment can use your custom account. With the default name,
the ESO Helm release owns `external-secrets` and no separate account is created.
For example, include this inside `orchestration.addons`:

```hcl
external_secrets_operator_values = {
  serviceAccount = {
    name = "custom-eso"
  }
}
```

`gcp.create_secret_store_service_account` controls wrapper ownership of the
fixed store account. By default, the wrapper manages it only when it installs
ESO and Helm does not create that account. Set this field to `false` to leave
an externally provisioned account unmanaged. With
`orchestration.addons.install_external_secrets_operator = false`, the default
is also unmanaged; ensure the external `external-secrets` account exists in the
installation namespace with the required GCP annotation. The default Helm-owned
account is never duplicated by Terraform, even if this field is `true`.

If `serviceAccount.create = false`, provision the operator's selected account
separately unless it is the fixed account managed by the wrapper. If the selected
account is `external-secrets` and is externally managed, you must add the
`iam.gke.io/gcp-service-account` annotation with value
`<customer_name>-eso@<project_id>.iam.gserviceaccount.com` to that account in
the installation namespace. Helm values do not annotate an account when
`serviceAccount.create = false`. A wrapper-managed fixed account receives the
annotation automatically; when the selected name differs, the wrapper still
creates the annotated fixed store account under the ownership rules above.

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
| `orchestration.values` | Ignored by the GCP wrapper, which supplies its own provider values. Use `orchestration.extra_values` for application-chart overrides. |
| `orchestration.extra_values` | List of Helm value objects for the application chart, merged after typed and provider values. |
| `orchestration.extra_values_yaml` | List of YAML strings for application-chart overrides, merged after `extra_values`. |

Prefer typed inputs over raw Helm values. Use `extra_values` for intentional
one-off overrides that should remain local to an environment. Both
`extra_values` and `extra_values_yaml` apply only to the application chart;
they do not configure the separate StarRocks Helm release.

## Deploy

If auth is enabled, complete the [secret bootstrap](#authentication-and-secret-manager)
and ensure a populated auth secret version exists **before the full apply**.
Saved plans can contain secret values. Store them in the same private directory
outside any Git checkout. From `gcp/zipline-orchestration`, initialize the
backend and review the plan:

```shell
umask 077
mkdir -p "$HOME/.config/zipline-bootstrap"
chmod 700 "$HOME/.config/zipline-bootstrap"
tofu init -reconfigure -backend-config=backend.hcl
tofu validate
tofu plan -out="$HOME/.config/zipline-bootstrap/customer.tfplan"
tofu apply "$HOME/.config/zipline-bootstrap/customer.tfplan"
```

After apply, configure kubectl and inspect the ingress controller Service:

```shell
tofu output -raw kubeconfig_command
# Run the command printed above, then inspect the Service's external IP:
kubectl get service zipline-orchestration-ingress-nginx-ui-controller \
  -n zipline-system -o jsonpath='{.status.loadBalancer.ingress[*].ip}{"\n"}'
```

Use your configured release name and namespace if they differ from
`zipline-orchestration` and `zipline-system`. Wait until the Service status shows
an external IP. Then refresh the stored output and read the DNS instructions:

```shell
tofu apply -refresh-only
tofu output -raw ingress_dns_instructions
```

Confirm the IP in the output matches the Service status before creating the
DNS A record for `orchestration.ingress.domain`. Inspect the installation:

```shell
kubectl get pods -n zipline-system
kubectl get ingress -n zipline-system
```

Verify DNS, TLS issuance, and application readiness before submitting jobs.


## Outputs

| Output | Use |
| --- | --- |
| `network`, `subnet`, `network_created` | Inspect the network used by the stack. |
| `gke_cluster_name`, `gke_cluster_endpoint` | Inspect the cluster; endpoint output is sensitive. |
| `kubeconfig_command` | Command to configure kubectl for the cluster. |
| `ingress_load_balancer_ip` | Inspect the wrapper-reserved IP; Helm overrides can change the effective Service IP. |
| `ingress_load_balancer_target` | Inspect the controller Service's published DNS target. |
| `ingress_dns_instructions` | Display the DNS A record to create for the configured ingress domain and IP. |
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

The Spark 4 helper jars from `FlinkConfigBuilder.spark4AdditionalJarNames`
must be published to `gcp.flink_jars_base_path` when set. Otherwise, the path is
`gs://<gcp.spark_libs_bucket>/spark-4.1.3/libs/` when `spark_libs_bucket` is
explicitly set, or `<artifact_prefix>/spark-4.1.3/libs/` when it is omitted.
`zipline admin install` publishes the jars there. Existing stacks using the
legacy bucket can preserve it with `spark_libs_bucket = "zipline-spark-libs"`
and `create_spark_libs_bucket = true`.

`gcp.kv_bulk_uploader` defaults to `"spark"`, which Polaris output requires.
Each streaming job needs its own Pub/Sub subscription, including when jobs in
separate stacks read the same topic; a subscription delivers each message to
only one reader.

## Notes

The shared chart bootstraps Polaris runtime authentication and writes the
`OC_CREDENTIAL` value into the `polaris-client-credentials` Kubernetes Secret.
The GCP wrapper configures a GCS catalog location under the warehouse bucket.

GKE, Cloud SQL, and Bigtable deletion protection default to enabled. Disable
and apply the corresponding protection settings before an intentional destroy.
Auth secrets remain externally managed and survive Terraform teardown.
Destroy also uses `gcloud` and `kubectl` to drain controller-managed resources.

`gcp.artifact_repository`, `gcp.compute_namespace_prefix`, and
`gcp.cloudflare_record_name` currently do not configure registry grants,
namespace creation, or DNS records. Use the documented image, compute namespace,
and external DNS configuration instead.

## Conf repository sandbox

Set `orchestration.conf_repo.url` to enable the repository editor and sandbox.
See the [sandbox configuration guide](../../charts/zipline-orchestration/SANDBOX.md)
for inputs, cloud secret references, and image availability requirements.
## Data Explorer

Data Explorer is enabled by default. Existing deployments that omit
`data_explorer` get StarRocks on their next apply. To keep it off, add this to
the `orchestration` object in your environment's tfvars:

```hcl
orchestration = {
  # Existing settings...
  data_explorer = {
    enabled = false
  }
}
```

StarRocks uses native GCS shared-data storage (`cloud_native_storage_type = "GS"`)
at `gs://<gcp.warehouse_bucket>/dataexplorer`. FE and CN pods use the orchestration
Kubernetes service account, which is bound to the orchestration Google service
account through GKE Workload Identity. The GKE metadata server supplies short-lived
credentials through the Compute Engine credential API. No HMAC keys or service
account private keys are needed. The existing warehouse bucket IAM grant provides
object access; installation waits for the bucket grants and identity binding.

This requires StarRocks 3.5.1 or newer; the shared module currently pins 4.1.3.
See the [StarRocks GCS configuration](https://docs.starrocks.io/docs/administration/configuration/FE_parameters/shared_lake_other/#gcp_gcs_use_compute_engine_service_account)
and [GKE metadata authentication](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/workload-identity#metadata-server).
Polaris catalog authentication and credential vending remain separate from
StarRocks' own shared-data storage authentication.

After enabling in a test environment, verify that FE and CN pods become ready,
the `starrocks-catalog-init` job succeeds, and `SHOW STORAGE VOLUMES` / `DESC STORAGE
VOLUME builtin_storage_volume` report native GCS storage. Query a known table in
`zipline_catalog` to verify Polaris credential vending and GCS reads end to end.

If you previously configured HMAC storage manually and have an initialized
StarRocks cluster, inspect its persisted storage volumes before applying. Changing
FE configuration does not constitute a migration of existing S3-type storage
volumes to GS. Plan that migration separately; do not delete PVCs or stored data.

## Cost tracking

Cost tracking is on by default. Set `cost_tracking.enabled = false` to turn it off. A daily Spark job (`ScheduledSparkApplication`
`cost-export` in the default compute namespace) reads the Cloud Billing detailed usage cost export
and writes `zipline_catalog.cost.daily_cost` in Polaris, one row per day, project, cluster,
namespace, service and SKU. Data Explorer can query it.

Until the billing export below exists, each daily run fails with a message saying to turn it on.

Prerequisites, done once by the customer:

1. Turn on **Detailed usage cost** export (Billing → Billing export → BigQuery export) into dataset
   `<gcp.project_id>.billing_export`, or any dataset set in `billing_export_dataset`.
2. GKE cost allocation is on through `gke_cost_allocation` (default `true`). Namespace splits only
   cover usage after it is turned on.

```hcl
orchestration = {
  # Existing settings...
  cost_tracking = {
    # All optional:
    # enabled                = true
    # billing_export_dataset = "<project>.<dataset>"  # default <gcp.project_id>.billing_export
    # projects               = ["<project>"]          # default [gcp.project_id]
    # schedule               = "0 6 * * *"
    # lookback_days          = 5
  }
}
```

The job runs as the compute namespace's Spark service account. If the export dataset is in another
project, Terraform grants that account `roles/bigquery.dataViewer` on the dataset, so the applying
identity needs permission to set IAM there. Each run rewrites the last `lookback_days` days, because
billing rows and credits keep arriving for a few days after usage.

Team is derived from the namespace: `zipline-<team>` maps to `<team>`; other namespaces, idle node
capacity (`kube:unallocated`) and costs outside Kubernetes map to `shared`.

## Sandbox network isolation

Sandbox networking uses an allowlisted egress proxy and NetworkPolicies.
See the [sandbox network guide](../../charts/zipline-orchestration/SANDBOX.md#sandbox-network-isolation)
for configuration, cluster enforcement, and rollout considerations.

## Agents UI configuration

Set `orchestration.agents.enable = true` to add `AGENTS=true` and
`AGENTS_LLM_PROXY_URL=http://orchestration-ui-service` to the UI container.
The URL points back to the UI as reached by the sandbox, using the UI Service's
port 80. Set `orchestration.agents.llm_proxy_url` to override that URL.
When `enable` is false or omitted, neither variable is added.
This configures the UI only; it does not provision agent runtime services.

### Agent provider API keys

Set `orchestration.agents.anthropic_api_key_remote_ref`,
`orchestration.agents.openai_api_key_remote_ref`, and/or
`orchestration.agents.gemini_api_key_remote_ref` to cloud secret references.
When agents are enabled, External Secrets syncs these into the UI through
`secretKeyRef` as `AGENTS_ANTHROPIC_API_KEY`, `AGENTS_OPENAI_API_KEY`, and
`AGENTS_GOOGLE_API_KEY`, respectively.
See [provider credential configuration](../../charts/zipline-orchestration/AGENT_CREDENTIALS.md)
for reference formats and examples. All references are optional.
