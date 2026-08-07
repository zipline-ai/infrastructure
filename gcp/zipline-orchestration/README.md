# GCP Zipline Orchestration

Creates the Google Cloud primitives for Zipline orchestration, installs the
shared `charts/zipline-orchestration` chart on a Standard GKE cluster, and wires
the GCP resources into cloud-neutral chart values.

The wrapper uses an existing GCP project. It enables the required project APIs
and manages Standard GKE, Workload Identity, GCS buckets, Secret Manager,
private-IP Cloud SQL for PostgreSQL, and Google Cloud Managed Service for
Prometheus. It can create a VPC, subnet, secondary ranges, and Cloud NAT, or use
an existing VPC and subnet. The shared `modules/zipline-orchestration` module
owns the common Helm values and chart installation.

The wrapper does not create a GCP project or manage DNS records. After apply,
use the ingress output with the DNS automation for the target environment.

## Prerequisites

- An existing GCP project with billing enabled.
- Permission to enable project services and create the resources listed above.
- OpenTofu, the Google Cloud CLI, and Application Default Credentials.
- A GCS bucket created separately for OpenTofu state.

Authenticate before running OpenTofu:

```shell
gcloud auth application-default login
gcloud config set project PROJECT_ID
```

## Configuration

Supply environment values through a local, git-ignored Terraform variable
file. The root accepts two top-level objects:

- `orchestration`: shared Zipline installation settings.
- `gcp`: GCP-specific infrastructure settings.

A minimal starting point is:

```hcl
orchestration = {
  deployment = {
    customer_name   = "example"
    artifact_prefix = "gs://example-artifacts/zipline/artifacts"
    zipline_version = "example-version"
  }

  ingress = {
    domain = "zipline.example.com"
  }
}

gcp = {
  project_id       = "example-project"
  region           = "us-central1"
  warehouse_bucket = "example-warehouse"
}
```

Do not commit variable files or put secret values in this README. Supply
sensitive values through the environment-specific secret workflow.

## Required Inputs

| Field | Why it is required |
| --- | --- |
| `orchestration.deployment.customer_name` | Prefixes generated resource names. |
| `orchestration.deployment.artifact_prefix` | `gs://` URI for Zipline artifacts. The wrapper creates the named bucket. |
| `orchestration.deployment.zipline_version` | Image tag used by Zipline services. |
| `orchestration.ingress.domain` | Public host used by Zipline ingress routes. DNS itself is managed elsewhere. |
| `gcp.project_id` | Existing project in which project services and resources are managed. |
| `gcp.region` | GCP region for GKE, networking, Cloud SQL, and regional resources. |
| `gcp.warehouse_bucket` | GCS bucket for the warehouse. The wrapper creates it. |

The artifact prefix must start with `gs://` and include the artifact bucket,
for example `gs://example-artifacts/zipline/artifacts`.
`orchestration.deployment.customer_name` must be 5-20 lowercase letters,
numbers, or hyphens, start with a letter, and end with a letter or number.

## Network

If `gcp.network` and `gcp.subnetwork` are empty, the wrapper creates a custom
VPC, a regional subnet, named pod and service secondary ranges, and Cloud NAT
for private nodes. Configure the CIDRs before the first apply so they do not
overlap the rest of the environment.

To use an existing network, set both `gcp.network` and `gcp.subnetwork`. The
subnet must have secondary ranges matching `gcp.pods_range_name` and
`gcp.services_range_name`. Set `gcp.network_project_id` when a Shared VPC is in
another project. The existing network must already support private service
access for the Cloud SQL connection created by this wrapper.

To let the wrapper create private service access on an existing network, set
`gcp.create_private_service_access = true`. For Shared VPC, the applying
principal needs the required host-project permissions and the Compute Engine
and Service Networking APIs must already be enabled in the host project.

Network options include:

| Field | Use when |
| --- | --- |
| `gcp.network`, `gcp.subnetwork` | GKE should use an existing VPC and regional subnet. Set both or neither. |
| `gcp.network_project_id` | The existing network belongs to a Shared VPC host project. |
| `gcp.network_cidr` | A created subnet needs a different primary CIDR. |
| `gcp.pods_range_name`, `gcp.pods_range_cidr` | Pod addresses or the existing secondary-range name must change. |
| `gcp.services_range_name`, `gcp.services_range_cidr` | Service addresses or the existing secondary-range name must change. |
| `gcp.private_nodes` | GKE nodes should have only private addresses. |
| `gcp.enable_private_endpoint` | The Kubernetes API endpoint should be private. Defaults to `true`. |
| `gcp.master_ipv4_cidr_block` | The private control-plane CIDR must fit the network plan. |
| `gcp.master_authorized_networks` | A public Kubernetes API endpoint should accept traffic only from approved CIDRs. |
| `gcp.create_cloud_nat` | A newly created VPC with private nodes needs managed outbound access. |
| `gcp.create_private_service_access` | The wrapper should allocate a private-service range and connection. Defaults to `true` for a created VPC and `false` for an existing VPC. |
| `gcp.private_service_prefix_length` | A wrapper-managed private-service range needs a size other than `/16`. |

If `gcp.enable_private_endpoint` is true, run OpenTofu from a network that can
reach the private GKE control-plane endpoint. The Kubernetes and Helm providers
must connect to that endpoint during apply.

If `gcp.enable_private_endpoint` is false, set
`gcp.master_authorized_networks` to at least one approved source CIDR. The
wrapper rejects a public control-plane endpoint without an allowlist.

## GKE Capacity

The wrapper creates a regional Standard GKE cluster with Workload Identity and
Managed Service for Prometheus enabled. It removes the default node pool and
creates a configurable system node pool. Use `gcp.node_pools` for additional
Spark, Flink, or other workload pools.

| Field | Use when |
| --- | --- |
| `gcp.cluster_name` | The cluster needs a stable or pre-approved name. |
| `gcp.kubernetes_version` | The environment must pin a Kubernetes version. |
| `gcp.release_channel` | GKE upgrades should follow a different channel. |
| `gcp.deletion_protection` | The cluster must be protected from accidental deletion. |
| `gcp.system_node_pool` | System capacity needs different machine, disk, autoscaling, labels, taints, or Spot settings. |
| `gcp.node_pools` | Compute workloads need additional pools with their own capacity and scheduling settings. |

Each additional node pool can set `initial_node_count`, `min_node_count`,
`max_node_count`, `machine_type`, `disk_type`, `disk_size_gb`, `image_type`,
`spot`, `labels`, `taints`, `auto_repair`, and `auto_upgrade`.

Node-pool labels and taints do not select workloads by themselves. When a pool
is tainted or reserved for a workload, set the matching node selectors and
tolerations in the relevant `orchestration` Helm values.

## Storage, Database, and Secrets

The wrapper creates artifact, warehouse, and logs buckets with uniform
bucket-level access. It creates a private-IP Cloud SQL PostgreSQL instance and
database, generates the database password, and stores the database credentials
in Secret Manager. Workload Identity grants Kubernetes service accounts only
the GCP roles required by their workloads.

| Field | Use when |
| --- | --- |
| `gcp.logs_bucket` | Logs need a specific bucket name. |
| `gcp.bucket_location` | Buckets should use another regional or multi-regional location. |
| `gcp.bucket_versioning_enabled` | Bucket object versioning should be enabled or disabled. |
| `gcp.bucket_force_destroy` | Non-empty buckets may be deleted with the stack. Use with care. |
| `gcp.database_name` | Zipline should use a different database name. |
| `gcp.database_instance_name` | Cloud SQL needs a stable instance name. |
| `gcp.database_version` | PostgreSQL must use another supported major version. |
| `gcp.database_tier` | Cloud SQL needs different CPU or memory capacity. |
| `gcp.database_disk_size` | Cloud SQL needs a different disk size. |
| `gcp.database_availability_type` | Cloud SQL should use zonal or regional availability. |
| `gcp.database_backup_enabled` | Automated backups should be enabled or disabled. |
| `gcp.database_deletion_protection` | The database must be protected from accidental deletion. |
| `gcp.database_username` | The generated database user needs a different name. |
| `gcp.database_credentials_secret_name` | The database credentials need a stable Secret Manager name. |
| `gcp.auth_secret_values` | Terraform should create configured authentication secrets. Keep values out of Git. |
| `gcp.auth_secret_ids` | Authentication uses existing Secret Manager secret IDs instead of creating their values. |
| `gcp.secret_force_destroy` | Secret Manager secrets may be deleted without deletion protection. Use with care. |
| `gcp.workload_roles` | A workload identity needs additional project IAM roles. |

## Apply

Create `backend.hcl` for an existing GCS state bucket. Do not put credentials in
the file:

```hcl
bucket = "example-opentofu-state"
prefix = "zipline-orchestration/gcp"
```

Then initialize and apply from this directory:

```shell
../../pull_crucible_config.sh gcp
tofu init -reconfigure -backend-config=backend.hcl
tofu plan
tofu apply
```

The configuration sync command is only needed for environments that store their
git-ignored backend and variable files in the configured GCS location.

## Observability and DNS

GKE Managed Service for Prometheus collects cluster metrics. The GCP chart
values create a `PodMonitoring` resource for orchestration Hub metrics. The
wrapper grants the workload identities the monitoring access needed to write
and query metrics and passes the GCP query endpoint to the shared chart.

DNS remains outside this wrapper. Use the ingress output after apply to create
or update the public DNS record with the environment's DNS tooling.
