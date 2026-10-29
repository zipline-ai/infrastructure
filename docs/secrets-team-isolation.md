# Per-team secret isolation on Crucible

Research as of 2026-10-09. Code refs: **infra** = `infrastructure@587d359` (origin/main), **platform** = `platform@e74435097` (origin/main). Live checks: read-only `kubectl` on `crucible-eks` and `aws iam` reads. No secret values were printed. Values were classified only as ARN, placeholder, or literal plus its length.

**Update (14 Oct).** platform#1384 (approved, not yet merged) covers the first of the two platform items in §3: Ray secrets now pass through as `*_VAULT_URI` refs and the trainer resolves them, so the Hub no longer holds them. The Hub-env `{NAME}` allowlist is still open, and `OC_CREDENTIAL` still needs a job-side home before it can come off that list. Everything else below is unchanged against `infrastructure@587d359`, which is still `origin/main`.

## 1. Current state

**One IAM role per engine, shared by every team.**

| Engine | K8s SA in `zipline-<team>` | IAM role (live annotation, same in both namespaces) | Secrets it can read (live IAM) |
|---|---|---|---|
| Spark | `spark-operator-spark` | `crucible-spark-compute-execution` | `databricks-client-secret`, `databricks-credential` |
| Flink | `flink` | `crucible-flink-compute-execution` | same two |
| Ray | `spark-operator-spark` (reuses the Spark SA) | Spark role | same two, but the Hub resolves Ray's secrets (see below) |
| Hub / eval | `orchestration-sa` (`zipline-system`) | `crucible-orchestration-irsa` | the two above plus `db-password`, `auth-secret`, `databricks-sp` |

- The compute roles trust *any* `zipline-*` namespace: `StringLike system:serviceaccount:zipline-*:spark-operator-spark` (infra `irsa.tf:240-245`, Flink `:391-395`; live trust policy matches). The chart puts one annotation on every namespace's SA (`compute-rbac.yaml:18-21, 62-65`; `locals.tf:284-293`). Changing annotations alone would not isolate teams, because any job holding that SA token can call STS for the shared role directly.
- The Databricks pair is attached to all three roles (`irsa.tf:618-641`). No team-specific secrets exist yet. Adding one today would mean granting it on the shared role, which makes it readable by every team.
- **Team creation is not dynamic today.** Namespaces, SAs and Roles are rendered from `compute.namespaces` in tfvars (`compute-namespace.yaml:3-7`, `compute-rbac.yaml:3-21`, `modules/.../main.tf:499,542,659`). The local tfvars copy lists `zipline-default` and `zipline-aws-databricks`. The submitter treats namespaces as provisioned, not created (platform `KubernetesCrucibleJobStore.scala:307-315`). Live `kubectl auth can-i` says the Hub **cannot** create namespaces, Secrets, or ExternalSecrets in team namespaces.
- Job SAs cannot `get secrets` (live: `no`), but they can create pods in their own namespace (live: `yes`, and `no` cross-namespace).
- **ESO today is platform-only.** There is one namespaced `SecretStore` in `zipline-system`, which authenticates as `orchestration-sa`, the Hub's role (`locals.tf:298-318`). It syncs two ExternalSecrets (`auth-secret`, `db-credentials`). There is no ClusterSecretStore, and team namespaces hold no Secrets. Chewy's open infra#186 adds a ClusterSecretStore (Hub identity, limited to namespaces labelled `compute`) and one Terraform-enumerated ExternalSecret per namespace, for the shared Redis password.

**Where resolved secrets end up in specs** (live, newest CRs):
- **Spark:** env travels as `spark.kubernetes.driverEnv.*` and `spark.executorEnv.*` (platform `CrucibleSubmitter.scala:242-245`). Live: `DATABRICKS_*_VAULT_URI` are ARNs, and `...oauth.clientSecret` / `...credential` are `{DATABRICKS_*}` placeholders. That is OK.
- **Flink:** only `FLINK_`-prefixed env becomes pod env (`CrucibleSubmitter.scala:79`). Live: the Databricks entries are placeholders. Its pod env is just `FLINK_CLASSPATH, JARS_URI, STATE_URI`, so those placeholders have no `*_VAULT_URI` to resolve from.
- **Ray: leaks.** The Hub resolves vault refs with *its own* role, interpolates, and strips the `RAY_` prefix (`NodeSubmitter.scala:200-210`, `CrucibleModelPlatform.scala:99`, `CrucibleKubernetesSpecs.scala:773`). Live RayJob pod env: `DATABRICKS_CLIENT_SECRET` is a 36-char literal.
- **Also leaks: the Polaris credential.** `spark.sql.catalog.zipline_catalog.credential` is a 49-char literal in all 3 SparkApplications and the FlinkDeployment I checked. Canary confs set it to `{OC_CREDENTIAL}`, and the Hub fills it from its own env (`locals.tf:378-389`, `NodeSubmitter.scala:61`). This is by design per infra `README.md:479-484`, but it contradicts #1380's "no resolved secret reaches the CR".
- **Hub as confused deputy (from reading the code, not tested).** The `{NAME}` fill uses the Hub's whole process env with no allowlist (`NodeSubmitter.scala:434-449`), and that env includes `DB_PASSWORD` (`orchestration-hub.yaml:56-60`). The Ray path resolves any `*_VAULT_URI` a team supplies, using the Hub role. So a team conf could likely pull Hub-only secrets into its own spec. Per-team IAM roles do **not** fix this. Only moving resolution out of the Hub does.

## 2. Options

| | Isolation | Teams / secrets: Terraform or dynamic? | Work (repo) | What breaks / caveats |
|---|---|---|---|---|
| **(a) Per-team IAM roles (IRSA) on per-namespace SAs** | Strong, enforced by AWS, even if the Hub or a conf is wrong | Roles: Terraform, generated from the existing `compute.namespaces` list, so no new onboarding step. Secrets: not enumerated if team policies use a name prefix (`<prefix>/teams/<ns>/*`) or a tag | infra: `for_each` roles + per-namespace SA annotations + narrow the shared trust. chronon/platform: none for Spark/Flink | Ray still resolves in the Hub until moved in-job. Role names are ≤64 chars, so long namespaces need truncate+hash. 2 roles per team (Spark, Flink) |
| **(b) `k8s://` provider (chronon#2232) + per-namespace k8s Secrets + RBAC** | Good between jobs (reads only the pod's own namespace). Real strength depends on **who copies which secret into which namespace** | Something must create a Secret per (team, secret): Terraform ExternalSecrets (like #186) or the Hub, which needs new RBAC | chronon: #2232 (+ timeouts). infra: `get secrets` on job Roles, a sync mechanism. platform: Ray | Ray resolves in the Hub, so a `k8s://` ref there would read `zipline-system`. No Python resolver exists for trainers. Secrets get copied into etcd (no customer KMS `encryption_config`, `eks.tf:74`) |
| **(c) ESO namespaced SecretStore per team** | Strong *only if* each store's identity is a per-team role, i.e. it needs (a) underneath. With today's shared role it gives none | Stores and ExternalSecrets can be created dynamically (Hub) safely, because IAM bounds each namespace | infra: (a) + a store per namespace + ESO RBAC. Consumption via (b) or `secretKeyRef` | Most moving parts. Reverses the Oct 7 "no ESO yet". A **ClusterSecretStore** has one identity for all namespaces: its namespace selector limits who may *use* it, not which secrets each namespace gets |
| **(d) Leave shared** | None. Every team reads every compute-role secret, plus Hub-readable secrets via the Ray path | n/a | none | Fine only while all teams are internal |

Variant of (a): **EKS Pod Identity** puts a `kubernetes-namespace` session tag on credentials. That allows one shared role with ABAC (`ResourceTag/zipline-team == PrincipalTag/kubernetes-namespace`) instead of per-team roles. It still needs one association per namespace/SA, plus the agent add-on. It also changes the credential chain, and Spark pins `WebIdentityTokenCredentialsProvider` for S3A (live `sparkConf`; `locals.tf:418`), which would break until changed.

## 3. Recommendation

Choose **(a) per-team IRSA roles**. It fits the Oct 7 decision: vault-URI refs straight from Secrets Manager, no ESO, no plaintext in Terraform. Team namespaces are already Terraform-enumerated, so it adds no onboarding step. Secrets do not need enumerating, and Spark and Flink need no code change. Keep (b) and (c) for when non-AWS backends or ESO are wanted. If that happens, back them with namespaced SecretStores on the (a) roles, and keep team secrets off a ClusterSecretStore.

**Smallest first step (one infra PR, no behavior change):**
1. `irsa.tf`: for each non-default entry in `compute.namespaces`, create `<prefix>-<ns>-spark` and `-flink` roles. Each trusts `StringEquals sub = system:serviceaccount:<ns>:<sa>` and gets the same base policies as today, the shared Databricks policy, and a team policy on `secret:<prefix>/teams/<ns>/*`.
2. `compute-rbac.yaml`: give the SA annotation a per-namespace override that falls back to today's value.
3. Narrow the shared roles' trust from `zipline-*` to `zipline-default`.

To verify: a `zipline-default` job referencing an ARN under the `aws-databricks` prefix should fail loudly with AccessDenied (`JobSecrets.scala:47`).

**Do alongside (platform), since (a) does not cover it:**
- Stop resolving Ray secrets in the Hub. Pass the `*_VAULT_URI` refs through and resolve them in the trainer. boto3 already picks up the Spark SA's IRSA role.
- Restrict the Hub-env `{NAME}` fill to an allowlist of non-secret names (`DATABRICKS_CLIENT_ID`, …). `OC_CREDENTIAL` needs a job-side home before it can come off that list.

## 4. Open questions

**Kumar:** With #2232, who creates the Secret in `zipline-<team>`: Terraform or the Hub at team sync? If the Hub does it through a ClusterSecretStore on the Hub role, could a team's `teams.py` name any Hub-readable ARN? What is the plan for Ray, given Python trainers and Hub-side resolution? Would `get` use `resourceNames`? (Pods in the namespace can already mount any Secret there.) Would you be OK with (a) landing first and `k8s://` becoming the path for non-AWS backends?

**Chewy:** Would #186's ClusterSecretStore stay limited to platform-wide secrets like Redis? Does a per-namespace SA-annotation override conflict with the shared-pool work? The Hub role has three secret policies that are not in this repo (`RDSSecretReadAccess`, `DatabricksSpSecretReadAccess`, `ZiplineAuthSecretReadAccess`). Where are those managed? Also, `databricks_client_secret` is a plaintext tfvars input that Terraform writes into Secrets Manager (`irsa.tf:575-593`), so it sits in state. Should we switch to an out-of-band secret plus an ARN input?

**Piyush:** Should each team get its own Databricks SP and Polaris principal, or is shared fine for now? That decides whether the Databricks policy stays on every team role. Does the Hub check that the submitting user belongs to `metaData.team`? The namespace is taken from the conf (`NodeSubmitter.scala:345-350`). Without that check, any of these options isolates jobs from each other but not users from other teams. Do customers bring existing ARNs that will not match a name prefix? If so, we would need per-team ARN lists in tfvars or tag-based policies.
