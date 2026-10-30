# Zipline on GCP — orchestration wrapper

GCP cloud wrapper for the shared `modules/zipline-orchestration` module.
Mirrors `aws/zipline-orchestration/` — one stack per customer project+region,
GKE as the only compute plane.

See `docs/gcp-orchestration-plan.md` for the full design.

## CLI prerequisites

Install both before `tofu init`:

- `gcloud` (Google Cloud SDK)
- `gke-gcloud-auth-plugin` (the helm/kubernetes providers call it via `exec`;
  `tofu` doesn't install it): `gcloud components install gke-gcloud-auth-plugin`

Also:
- `tofu` 1.9+
- authenticated session: `gcloud auth application-default login`

## Bootstrap (one-time per cloud, not per customer)

GCS backends can't create the state bucket they live in, and the config bucket
has to exist before `pull_crucible_config.sh` can round-trip tfvars. Both are
one-time setup; the plan §5.1 locks in that GCP shares the AWS config bucket
(`zipline-crucible-vars`) under a `gcp/` key prefix.

### State bucket (per-stack)

```sh
gcloud storage buckets create gs://zipline-crucible-state-gcp \
  --project=canary-443022 \
  --location=us-central1 \
  --uniform-bucket-level-access
gcloud storage buckets update  gs://zipline-crucible-state-gcp --versioning
```

### Config bucket (shared with AWS)

If the AWS Crucible config bucket already exists, you don't need to create
anything — just confirm you can list it from gcloud. Otherwise (fresh install
or GCP-only org), seed it:

```sh
gcloud storage buckets create gs://zipline-crucible-vars \
  --project=canary-443022 \
  --location=us-central1 \
  --uniform-bucket-level-access
```

## Per-customer config: pull / push / diff

The repo-root scripts round-trip the git-ignored local files
(`backend.hcl`, `crucible.auto.tfvars.json`, optional `dns-provider.tf`,
`dns.auto.tfvars.json`, `.terraform.lock.hcl`) through the config bucket. All
land in this directory and are covered by `.gitignore`.

```sh
# Fetch (overwrites local)
./pull_crucible_config.sh gcp

# Edit values, then upload
./push_crucible_config.sh gcp

# Compare local to remote
./diff_crucible_config.sh gcp
```

Overrides via env (defaults in parentheses):

- `CRUCIBLE_CONFIG_BUCKET` (`zipline-crucible-vars`)
- `CRUCIBLE_CONFIG_KEY`    (`gcp/zipline-orchestration/crucible.auto.tfvars.json`)
- `CRUCIBLE_CONFIG_ROOT`   (`gcp/zipline-orchestration`)

### First-time seed (no remote config exists yet)

```sh
cd gcp/zipline-orchestration
cp crucible.auto.tfvars.example crucible.auto.tfvars.json
# edit secrets and OAuth client IDs

cat > backend.hcl <<EOF
bucket  = "zipline-crucible-state-gcp"
prefix  = "zipline-orchestration/crucible"
EOF

../../push_crucible_config.sh gcp
```

The tfvars file must contain top-level `orchestration` and `gcp` objects —
the pull/push scripts fail-fast with jq if either is missing.

## Apply

```sh
./pull_crucible_config.sh gcp       # or seed as above

cd gcp/zipline-orchestration
tofu init -backend-config=backend.hcl
tofu validate
tofu plan                            # safe, no changes applied
tofu apply                           # when ready
```

## Known gaps / Phase-gated capabilities

Phase 1 lands infra + a healthy chart; live workloads unlock in later phases:

- Phase 2 (batch) needs the GCP platform PR (§3.3 items 1–5) + arm64 image
  manifest for `ziplineai/spark:nightly` (§3.3 item 8).
- Phase 3 (online fetcher) uses what Phase 2 wires.
- Phase 4 (streaming/Flink) needs the Flink jar set published to
  `gs://zipline-spark-libs/spark-4.1.3/libs/`, Chronon-side `"gcp"` entry in
  `FlinkConfigBuilder.spark4CloudAdditionalJarNames` (§3.3 item 6), GCS
  connector in the Flink image (§3.3 item 7), arm64 Flink image (§3.3 item 8).
- Phase 5 (Ray training) needs Ray history collector wiring.

Hub pod should start cleanly in Phase 1 but any job submission will fail
until §3.3 lands and `hub-gcp` is rebuilt.

## Conf repository sandbox

Set `orchestration.conf_repo.url` to enable the internal sandbox and repository
editor configuration. See the [sandbox configuration guide](../../charts/zipline-orchestration/SANDBOX.md)
for inputs, cloud secret references, and image availability requirements.
