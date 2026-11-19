---
name: zipline-onboarding
description: Deploy Zipline into a customer's GCP or AWS account with the zipline-ai/infrastructure stack, check it with zipline admin doctor, and run a first backfill before the Zipline onboarding call. Use when asked to set up or onboard Zipline, or to prepare for the onboarding call. Do not use for authoring or debugging feature configs (use the zipline skill from `zipline init-agent`), for changing the Terraform modules, or for operating an existing deployment.
---

# Zipline onboarding

You are preparing the customer's environment before their onboarding call with Zipline. The goal is a working deployment and one successful backfill. If you can't get there, the goal is a short, precise list of blockers. The call goes over the blockers, so a clear failure report is as useful as a green run.

## Non-negotiable rules

- Never print, log or commit the Docker Hub token, `terraform.tfstate`, or any credential. Keep `zipline.auto.tfvars.json` out of git.
- Don't run `tofu destroy` or `tofu state rm`, and don't delete buckets, while onboarding is in progress. If cleanup is needed, propose it at the end, after every step is verified, and run it only when the human says yes.
- Don't edit files under `modules/` or `charts/` in the infrastructure repo. Only `*.auto.tfvars.json` and `backend.hcl` are yours to write. If a fix seems to need a module change, record it as a blocker.
- Get to the end goal fast. Start Steps 2 and 3 as soon as `tofu apply` has created the artifact bucket, and run them alongside the rest of Step 1.
- Each step ends with a **gate**. If a gate fails, check the troubleshooting table. If no row matches, retry at most once, then record a blocker and stop or move on as the step says.
- Keep `zipline-onboarding-report.md` in the working directory up to date (format at the end).

## Inputs to collect from the human first

| Input | Example | Notes |
|---|---|---|
| Cloud | `gcp` or `aws` | |
| Customer name | `acme` | usually the company name, short and a single word; names buckets and the cluster |
| GCP project ID / AWS account | `acme-ml-prod` | the human must be signed in with owner-level rights |
| Region | `us-central1` / `us-west-2` | |
| Zipline release | `1.30.1` | from Zipline |
| Docker Hub token | — | from Zipline; ask the human to put it in the env var `ZIPLINE_DOCKERHUB_TOKEN`, don't ask them to paste it to you |
| A source table to test with | `analytics.purchases` | a partitioned event table with a user key and an epoch-millis or timestamp column |
| Team contact email | `ml-platform@acme.com` | |

Set them as shell variables used below: `CLOUD`, `CUSTOMER`, `PROJECT` (GCP), `REGION`, `RELEASE`.

## Step 0: Prerequisites

Run each check. Report missing tools to the human with the install link; don't install system packages without asking.

```sh
tofu version            # >= 1.9
kubectl version --client
docker info             # daemon must be running
pipx --version
# GCP
gcloud version && gke-gcloud-auth-plugin --version
gcloud auth list --filter=status:ACTIVE --format='value(account)'
gcloud auth application-default print-access-token >/dev/null && echo adc-ok
# AWS
aws --version && aws sts get-caller-identity
```

GCP only:

```sh
gcloud config set project "$PROJECT"
gcloud auth application-default set-quota-project "$PROJECT"
```

**Gate:** every check passes. If sign-in fails, ask the human to sign in; don't continue.

## Step 1: Infrastructure

If you're not already in a checkout of this repository, clone it first.

```sh
git clone https://github.com/zipline-ai/infrastructure.git
cd infrastructure/$CLOUD/zipline-orchestration
```

1. **State bucket.** Name it `zipline-$CUSTOMER-tofu-state`. If it already exists, reuse it.
   - GCP:
     ```sh
     gcloud storage buckets create gs://zipline-$CUSTOMER-tofu-state --location=$REGION \
       --uniform-bucket-level-access --public-access-prevention
     gcloud storage buckets update gs://zipline-$CUSTOMER-tofu-state --versioning
     printf 'bucket = "%s"\nprefix = "zipline-orchestration"\n' "zipline-$CUSTOMER-tofu-state" > backend.hcl
     ```
   - AWS:
     ```sh
     aws s3api create-bucket --bucket zipline-$CUSTOMER-tofu-state --region $REGION \
       --create-bucket-configuration LocationConstraint=$REGION
     aws s3api put-bucket-versioning --bucket zipline-$CUSTOMER-tofu-state --versioning-configuration Status=Enabled
     aws s3api put-public-access-block --bucket zipline-$CUSTOMER-tofu-state \
       --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
     printf 'bucket = "%s"\nkey    = "zipline-orchestration/terraform.tfstate"\nregion = "%s"\n' "zipline-$CUSTOMER-tofu-state" "$REGION" > backend.hcl
     ```
   In `us-east-1`, drop `--create-bucket-configuration`.

2. **Settings.** Write `zipline.auto.tfvars.json` with only these keys. Everything else has a default.
   ```sh
   python3 - <<'EOF'
   import json, os
   c, cloud = os.environ["CUSTOMER"], os.environ["CLOUD"]
   cfg = {"orchestration": {
            "deployment": {"customer_name": c,
                           "zipline_version": os.environ["RELEASE"]},
            "image_pull_secret": {"create": True, "dockerhub_token": os.environ["ZIPLINE_DOCKERHUB_TOKEN"]}}}
   cfg[cloud] = {"region": os.environ["REGION"]}
   if cloud == "gcp":
       cfg["gcp"]["project_id"] = os.environ["PROJECT"]
   json.dump(cfg, open("zipline.auto.tfvars.json", "w"), indent=2)
   EOF
   ```
   If the human wants to use an existing network, add `gcp.network` and `gcp.subnet` (the subnet needs secondary ranges named `pods` and `services`), or `aws.vpc_id`, `aws.primary_subnet_id` and `aws.secondary_subnet_id`. Otherwise the stack creates a new one.

3. **Plan and apply.**
   ```sh
   tofu init -backend-config=backend.hcl
   tofu apply -auto-approve                  # 20–40 min
   ```
   Run apply in the background and check on it every few minutes. Don't treat a long quiet stretch as a hang. Meanwhile, wait for the artifact bucket, then start Steps 2 and 3:
   ```sh
   # GCP
   until gcloud storage buckets describe gs://zipline-$CUSTOMER-artifacts >/dev/null 2>&1; do sleep 30; done
   # AWS
   until aws s3api head-bucket --bucket zipline-$CUSTOMER-artifacts 2>/dev/null; do sleep 30; done
   ```

   If apply fails on a `kubernetes_*` or `helm_release` resource, run `tofu apply` (fresh plan) again, up to 2 more times. This is expected on a new cluster.

4. **Outputs.**
   ```sh
   export ZIPLINE_HOST=$(tofu output -raw ingress_load_balancer_target)
   export HUB_URL="http://$ZIPLINE_HOST/services/hub"
   eval "$(tofu output -raw kubeconfig_command)"
   curl -s -o /dev/null -w '%{http_code}\n' "http://$ZIPLINE_HOST/"
   ```

**Gate:** apply finished with no errors, and the UI URL returns 200 or a 3xx. On AWS the load balancer hostname can take a few minutes to resolve, so retry for up to 10 minutes.

## Step 2: CLI

```sh
pipx install "zipline-ai==$RELEASE"
zipline --version
```

**Gate:** the version printed matches `$RELEASE`. If `which zipline` points somewhere other than pipx's bin directory, report it to the human. Another install shadows it.

## Step 3: Engine artifacts

```sh
zipline admin install $CLOUD --api-token "$ZIPLINE_DOCKERHUB_TOKEN" --release "$RELEASE" \
  --artifact-prefix "$( [ $CLOUD = gcp ] && echo gs || echo s3 )://zipline-$CUSTOMER-artifacts"
```

**Gate:** the output ends with `All artifacts loaded successfully.` (about 10 minutes).

## Step 4: Doctor

```sh
zipline admin doctor infra-health --cloud $CLOUD -y --report-file doctor-report.tsv
```

**Gate:** no FAIL rows. Copy any WARN or FAIL row into the report.

## Step 5: Config repo

```sh
cd ..   # outside the infrastructure repo
zipline admin init $CLOUD --customer-id "$CUSTOMER" --region "$REGION" \
  $( [ $CLOUD = gcp ] && echo --project-id "$PROJECT" ) --chronon-root ./zipline
cd zipline && git init
```

Fill the remaining placeholders in `teams.py`:
- `HUB_URL` → `$HUB_URL`
- `FRONTEND_URL` → `http://$ZIPLINE_HOST`
- `email` → team contact email
- partition column and format → match the test table

Then `grep -n '<' teams.py` must show no remaining `<...>` placeholders.

**Point the sample at the human's table:**
- **GCP:** edit `staging_queries/test/purchases_import.py` so it selects from the human's table, with `engine_type=EngineType.BIGQUERY`. Native BigQuery tables can't be read directly by Spark. In `sources/`, reference it as `table=purchases_import.v1.table`, a Python reference without quotes.
- **AWS:** point the source at the Glue table `<database>.<table>`.
- Set the source's `start_partition` to no more than 7 days before the backfill start. Each day back is one more import step.
- Adjust `selects`, the key column and `time_column` to the real columns. Ask the human if the mapping is unclear.

```sh
zipline compile
```

**Gate:** compile succeeds with no errors.

## Step 6: Backfill

Pick a 7-day range the test table has data for.

```sh
zipline hub backfill compiled/joins/test/<join-name> --start-ds <start> --end-ds <end>
```

The command prints a link to the run in the Zipline UI. Give it to the human and ask them to report the status. If a step fails, ask them for the error shown in that step's logs and copy its first line into the report.

**Gate:** every day succeeds. The output table shows up under **Data** in the UI as `zipline_catalog.default.<team>_<name>`.

## Step 7: Cost tracking (GCP only)

The stack turns cost tracking on by default; it needs the Cloud Billing detailed usage cost export. Ask the human (it needs the Billing Account Administrator role) to go to **Billing → Billing export → BigQuery export** in the Cloud console and, under **Detailed usage cost**, export to a dataset named `billing_export` in `$PROJECT`. You can't do this step from the CLI. Record in the report whether it's done.

## Troubleshooting

| Symptom | Action |
|---|---|
| `tofu init`: `"bucket": required field is not set` | `backend.hcl` missing or not passed; redo Step 1.1. |
| `tofu apply`: `tls: bad record MAC` or `Provider produced inconsistent final plan` | Re-run apply (up to 2 more times). If TLS errors persist, ask the human to drop VPN/proxy. |
| `tofu apply`: GCP `ZONE_RESOURCE_POOL_EXHAUSTED` / stockout | Blocker. Report the zone and machine type; Zipline will advise a region or machine type. |
| gcloud warning about quota project | `gcloud auth application-default set-quota-project $PROJECT` |
| `admin install`: `Cannot connect to the Docker daemon` | Ask the human to start Docker. |
| Backfill: `Direct table reads are not supported for BigQueryNative format` | Source reads a native BigQuery table; use the BigQuery staging-query export. |
| Backfill: `CATALOG_NOT_FOUND` naming a staging-query module | Source `table=` is a quoted string; use the unquoted Python reference. |
| Backfill: table or column not found | Check the source table name and `selects` against the real table with the human. |
| UI shows `Error: 403` on a write | No-auth setups give everyone the operator role. Some pages need admin. Record as a blocker; don't change auth. |
| Logs tab empty | Wait a minute after the job starts and refresh. |

## Report format

Write `zipline-onboarding-report.md`:

```markdown
# Zipline onboarding report: <customer> (<cloud>, release <release>)

| Step | Status | Duration | Notes |
|---|---|---|---|
| 0 Prerequisites | ✅/❌/⏭ | | |
| 1 Infrastructure | | | apply attempts: N |
| 2 CLI | | | |
| 3 Engine artifacts | | | |
| 4 Doctor | | | WARN/FAIL rows |
| 5 Config repo | | | |
| 6 Backfill | | | join, date range |
| 7 Cost tracking (GCP) | | | billing export on? |

UI: http://<ZIPLINE_HOST>/

## Blockers
For each: step, exact command, first error line (secrets redacted), what you tried.

## Changes made outside the defaults
Any tfvars beyond the minimal set, IAM or API changes, and why.
```

Hand the report to the human at the end and tell them to bring it to the onboarding call.
