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
The chart owns service defaults such as per-service ingress annotations, image
repositories, fetcher replicas, and Polaris bootstrap defaults. Use
`orchestration.extra_values` only for intentional one-off Helm overrides.

Networking intentionally matches Azure at the chart boundary: cloud load
balancers pass traffic to ingress-nginx, and Kubernetes Ingress TLS secrets own
TLS termination. ACM-specific load balancer TLS termination can still be layered
through `extra_values`, but is not the default shared path.

## Crucible Canary Overrides

Crucible canary settings are stored outside the repo and pulled locally when
planning or applying:

```shell
./pull_crucible_config.sh
```

The script downloads the raw legacy inputs into `.crucible-config/raw/` without
placing legacy `github.tf`, `cloudflare.tf`, or `terraform.tfvars` files in this
Terraform root. Use those raw files plus live Helm values to create a local
ignored `*.auto.tfvars.json` for this Helm adoption wrapper.

Canary inputs should be grouped into shared and provider-specific objects:

```hcl
orchestration = {
  install = {
    namespace    = "zipline-system"
    helm_wait    = true
    helm_timeout = 300
  }
  deployment = {
    customer_name   = "crucible"
    artifact_prefix = "s3://zipline-artifacts-crucible"
    zipline_version = "nightly"
  }
  database = {
    host = "example.postgres.amazonaws.com"
  }
  ingress = {
    domain = "crucible-aws.zipline.ai"
  }
}

aws = {
  region                 = "us-west-2"
  cluster_name           = "crucible-eks"
  database_secret_arn    = "arn:aws:secretsmanager:us-west-2:123456789012:secret:zipline-db"
  warehouse_bucket       = "zipline-warehouse-crucible"
  orchestration_role_arn = "arn:aws:iam::123456789012:role/orchestration"
  spark_compute_role_arn = "arn:aws:iam::123456789012:role/spark-compute"
  flink_compute_role_arn = "arn:aws:iam::123456789012:role/flink-compute"
  polaris_storage_role_arn = "arn:aws:iam::123456789012:role/polaris-storage"
}
```

This wrapper should use the dedicated Helm adoption state key, not the old full
AWS infrastructure state:

```shell
tofu init -reconfigure \
  -backend-config=bucket=zipline-ai-opentofu-state-bucket \
  -backend-config=key=opentofu-crucible-zipline-orchestration-state \
  -backend-config=region=us-west-1 \
  -backend-config=encrypt=true
```

If the remote canary inputs need to be updated intentionally, edit the raw files
under `.crucible-config/raw/` and run:

```shell
./push_crucible_config.sh
```
