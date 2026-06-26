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
  cluster_name           = "example-eks"
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
