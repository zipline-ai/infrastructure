# AWS Public Demo Datasources

Persistent datasource layer for the public Zipline demo. This layer is separate
from `../zipline-orchestration` so weekly platform resets can destroy and
recreate EKS/RDS/Zipline without deleting historical demo datasets.

It creates:

- S3 raw and curated demo buckets.
- Glue databases and external tables for demo sources.
- A Kubernetes UI/server access-log harvester over CloudWatch container logs.
- A Lambda ingestor invoked by EventBridge schedules.

The default schedule is deliberately slow to keep early demo cost low. Change
`ui_logs_freshness_profile` when freshness matters more.

## Freshness Lever

Use `ui_logs_freshness_profile` as the main offline/online consistency demo
lever:

- `low_cost`: harvest UI/server logs every 30 minutes with a 30 minute lookback.
- `balanced`: harvest every 5 minutes with a 5 minute lookback.
- `fresh`: harvest every minute with a 1 minute lookback.

This source is intentionally relatable: if the UI is producing 404s, 500s, slow
requests, or surprising DELETE/PUT traffic, stale data makes the demo platform
look healthy when it is not.

Set the profile in `public-demo-datasources.auto.tfvars`, run `tofu apply`, and
EventBridge will update the harvesting cadence. The default remains `low_cost`.

All datasource tables are partitioned by `snapshot_date` only. Keeping minute
level freshness in columns instead of partition keys makes Chronon partition
readiness predictable for the demo.

## Configure

Create git-ignored config beside this README:

```shell
cp public-demo-datasources.auto.tfvars.example public-demo-datasources.auto.tfvars
```

Create `backend.hcl` for the persistent datasource state, then upload both
files:

```shell
../../push_public_demo_datasources_config.sh
```

## Deploy

```shell
../../pull_public_demo_datasources_config.sh
tofu init -backend-config=backend.hcl
tofu apply
```

The UI/server log source does not require a token. It reads from the EKS
container log group populated by Fluent Bit in the platform layer. By default
the log group is:

```shell
/aws/eks/public-demo-eks/containers
```

Override `ui_logs_log_group_name` only if the platform layer uses a different
log group.

## Connect To The Platform Layer

Grant the platform compute roles access to the datasource buckets by adding the
curated bucket to the orchestration tfvars:

```hcl
aws = {
  additional_data_buckets = [
    "zipline-public-demo-curated",
  ]
}
```

