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

## Crucible Canary Overrides

Crucible canary settings are stored outside the repo in S3 and pulled locally
when planning or applying:

```shell
../../pull_crucible_config.sh aws
```

By default the script reads from bucket `zipline-crucible-vars` and key
`zipline-orchestration/crucible.auto.tfvars.json`. Override those with
`CRUCIBLE_CONFIG_BUCKET` and `CRUCIBLE_CONFIG_KEY` if needed.

The script downloads one git-ignored file into this Terraform root:

- `crucible.auto.tfvars.json`

The stored file is expected to already use the wrapper structure; the script
does not translate legacy flat tfvars.

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

`flink_compute_role_arn` can be omitted when Flink should use the same service
account annotation as Spark.

This wrapper should use the dedicated Helm adoption state key, not the old full
AWS infrastructure state:

```shell
aws eks update-kubeconfig --region us-west-2 --name crucible-eks

tofu init -reconfigure \
  -backend-config=bucket=zipline-ai-opentofu-state-bucket \
  -backend-config=key=opentofu-crucible-zipline-orchestration-state \
  -backend-config=region=us-west-1 \
  -backend-config=encrypt=true
```

If the remote canary inputs need to be updated intentionally, edit the local
ignored `crucible.auto.tfvars.json` and run:

```shell
../../push_crucible_config.sh aws
```
