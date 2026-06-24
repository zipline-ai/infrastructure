# AWS Zipline Orchestration

Installs the shared `charts/zipline-orchestration` chart on EKS and wires AWS
infrastructure into cloud-neutral chart values.

AWS-specific work stays at this layer:

- IAM role annotations for orchestration and compute service accounts.
- AWS Secrets Manager objects projected through the generic chart
  `secrets` values.
- Optional AWS Secrets Store CSI provider.
- Optional AWS Load Balancer Controller.
- NLB annotations on the shared ingress-nginx controller Services.

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
