# Public-demo external GPU training

Review only, 2026-11-10. No apply, image publication, reservation or paid GPU run
was performed. All new resources default off. The existing CPU pools and quotas
are unchanged. This is infrastructure for Platform [PR #1461](https://github.com/zipline-ai/platform/pull/1461)
at `c883f570745449e883417ef66a5bb2ee35231eee`; no Platform, Chronon or trainer code is changed.

Use [integration.json](integration.json) for the non-secret machine contract,
[example.tfvars.example](example.tfvars.example) for opt-in inputs, [aws-evidence.json](aws-evidence.json)
for current pricing/quotas/offerings, and [plan-summary.json](plan-summary.json) for
plan coverage and limitations. Values under `proposed` are **not provisioned**.

## Verified environment and open prerequisites

**Additional deployment blocker found in independent review:** the current
`aws-eks-nodeagent` runs with `--enable-network-policy=false` and standard mode.
The namespace NetworkPolicy in this PR is not enforcement by itself. Enabling
training now requires `network_policy_enforcement_verified=true`, default false,
only after an approved CNI configuration and connectivity tests prove isolation
from the first packet. The example deliberately leaves this false. Do not set it
to bypass a failed prerequisite. CNI changes affect cluster networking and belong
in a separately reviewed deployment plan; none were made here.

The policy permits intra-development-namespace traffic, CoreDNS, outbound HTTPS
for AWS APIs, and KubeRay operator ingress on 8265. It blocks access to other
namespaces' unauthenticated Ray Jobs/GCS/client ports. Verify both ClusterIP and
pod-IP rejection with controller-owned CPU probe pods, including startup, while
same-namespace Ray traffic, DNS, HTTPS and operator access remain usable. Use
strict policy initialization or equivalent tested deny-from-first-packet behavior;
standard-mode initial allow windows are not sufficient. A policy-object read or a
version check cannot substitute for this test. No traffic enforcement is claimed
from the local kind admission tests.

Read-only AWS and Kubernetes inspection verified account `345594603419`,
`public-demo-eks`, `us-west-2`, EKS 1.36; subnets are in `us-west-2a` (`usw2-az1`)
and `us-west-2b` (`usw2-az2`). Both proposed instance types have offerings in both
AZs. No GPU instance was running in this account in Oregon or Virginia when
checked. No Kubernetes node advertised GPUs. DCGM exporter exists, but there is
no NVIDIA device plugin. Karpenter is 1.13.0.

KubeRay 1.7.0 is installed twice, in `kuberay-operator` and `zipline-system`, both
with leader election and `RayJobDeletionPolicy=true`. The v1 RayJob CRD has
`activeDeadlineSeconds` and `preRunningDeadlineSeconds`. Before enabling jobs,
establish one authoritative operator scope/leader and remove or scope the duplicate
through its owning deployment. This PR does not silently uninstall an existing
operator. Verify the chosen operator watches `zipline-s6e11-dev`.

The existing datasource tfvars are stale: they reference removed Caltrain inputs,
a nonexistent `zipline-public-demo-caltrain-curated` bucket, and omit required
`warehouse_bucket`. Do not run a broad datasource apply using that file. Reconcile
its backend/config with deployed resources separately; the targeted retained-resource
plan does not validate the rest of that module.

## Capacity and enforcement

Only one profile is selected at a time. Both are off unless `gpu_training.enabled`
is true. Explicit profile/type mismatches, Spot, unsupported node counts, unpinned
AMIs, empty identity/retention inputs and AZs outside the two configured subnets
fail validation. Selecting a profile does not prewarm it.

| Profile | Worker node ceiling | Maximum main worker container | Local disk / shared memory |
|---|---|---|---|
| `s6e11-l40s` / `g6e.xlarge` | 4 vCPU, 32 GiB, 1 L40S | 2 CPU, 24 GiB, 1 GPU | 100 GiB ephemeral / 8 GiB shm |
| `s6e11-a100` / `p4d.24xlarge` | 96 vCPU, 1152 GiB, 8 A100 | 88 CPU, 1024 GiB, 8 GPU | 1000 GiB ephemeral / 64 GiB shm |
| Two A100 nodes, gated extension | 192 vCPU, 2304 GiB, 16 GPU | Two pods, each 88 CPU / 1024 GiB / 8 GPU | Same per pod |

The G6e has 250 GB NVMe and 45,776 MiB GPU memory per the EC2 API. P4d has
8 × 1000 GB NVMe and 8 × 40,960 MiB GPUs. Host RAM is not GPU RAM. Karpenter
configures NVMe RAID0 as ephemeral storage. Each node also has an encrypted
100 GiB gp3 root for boot/image headroom. Confirm actual image layers, kubelet
image filesystem, allocatable disk and DaemonSet overhead on the first node;
none of these are durable checkpoint locations.

Head and submitter select a separate AMD64 `m6i.2xlarge` pool, limited to one
8-vCPU/32-GiB node. The head requests 2 CPU/8 GiB; submitter 500m/1 GiB (2 GiB
memory limit); Ray's autoscaler adds 500m/512 MiB (1 GiB limit). Namespace quota
adds 6 CPU/16 GiB to worker capacity for these containers and injected helpers.
G6e aggregate quota is 8 CPU/40 GiB/1 GPU; P4d is 94 CPU/1040 GiB/8 GPU;
two P4d is 182 CPU/2064 GiB/16 GPU. Requests and CPU/memory limits are separate
quota entries; extended GPU quota uses Kubernetes' `requests.nvidia.com/gpu`.

Admission also validates RayCluster writes by the shared autoscaler SA, preserves
cleanup ownership/finalizers, and rejects orphan deletion. RayJob specs are
immutable after submission; cancellation uses named cascading deletion. Pod
termination grace and caller DELETE grace overrides are capped at 120 seconds. Baseline
Pod Security prevents host-network/hostPath/privileged pods, including those
created by the operator. The supported path has no GCS fault tolerance.

Quota admits at most one RayJob and one RayCluster. Completed RayJobs remain up
to six hours under Platform's policy and consume the object-count quota; after
saving evidence, delete the **named** completed RayJob before the next run.
LimitRange supplies defaults for operator-injected containers. Admission bounds
worker topology, per-worker RAM/CPU, GPU count, placement, service accounts,
zero job retries, deadlines and cluster cleanup rules. CPU heads cannot request
GPUs. Role-specific selectors and profile-specific taints isolate existing CPU
jobs from these workers. Cluster administrators remain able to override controls.

Karpenter limits are eventually consistent provisioning ceilings, **not strict
node counts or dollar caps**; concurrent reconciliation can overshoot. Admission
and quotas constrain workload demand, but do not bound sequential run count or
billing during controller/API failure. GPU/control pools have no replicas or warm
Deployment, `expireAfter=Never`, `WhenEmpty` consolidation after one minute, and
zero drift/underutilization disruption budget. Manual deletion, EC2 failure and
cloud maintenance can still interrupt jobs. Do not change profiles with active
jobs. No production-wide quota is raised.

## Driver, image and Platform interface

SSM verified the NVIDIA AMI `ami-0e3d4bd8ae097dc7e`,
`amazon-eks-node-al2023-x86_64-nvidia-1.36-v20261107`. Dedicated AL2023 classes use
`al2023@v20261107`; Karpenter selects the NVIDIA variant for the GPU instance and
the standard variant for CPU control. Reverify the release for a different EKS
version/region. [Karpenter AMI selection](https://karpenter.sh/docs/concepts/nodeclasses/)
and [AWS device management](https://docs.aws.amazon.com/eks/latest/userguide/device-management.html)
explain this split: AL2023 includes drivers/runtime but requires the device plugin.

One pinned NVIDIA device-plugin Helm release, version 0.17.1, selects only marked
AMD64 GPU nodes, tolerates the exact Platform taints and fails on initialization
errors. NFD/GFD, sharing and GPU Operator are not enabled. The upstream chart also
renders a dormant MPS-control DaemonSet requiring `nvidia.com/mps.capable=true`;
this module never labels nodes MPS-capable. It does not install a second device
plugin. Existing NVIDIA deployments must be reconciled before enabling, rather
than installing another release on the same nodes.

The demo image must be an immutable Linux AMD64 ECR digest with Ray **2.55.1**
on every role, CPU-startable Ray/Python dependencies, CUDA userspace and PyTorch.
The host driver stays in the AMI. [NVIDIA compatibility](https://docs.nvidia.com/deploy/cuda-compatibility/minor-version-compatibility.html)
gives CUDA 12.x a Linux baseline of 525.60.13 and CUDA 13.x 580; PTX/new features
can require newer drivers. Verify the actual `nvidia-smi` driver and the exact
image's CUDA/PyTorch combination. No loaded driver or CUDA execution is claimed.
Memory-backed `/dev/shm` counts against the worker's memory limit; it is not extra
RAM. Head Ray tasks advertise zero CPU/GPU, so training must run on workers.

The actual keys are `ray.placement.profile`, `ray.worker.gpus`,
`ray.worker.replicas`, `ray.worker.shm`, `ray.worker.ephemeral-storage`,
`ray.architecture`, `ray.timeout.seconds`, `ray.region`, plus head/worker CPU/RAM.
Older hyphenated/singular proposals are not accepted. `ray.region` asserts region;
it does not route to another cluster. Platform adds required same-job hostname
anti-affinity. Labels and taints in the manifest exactly match its renderer.

The local launcher follow-up must forward `CRUCIBLE_RAY_GPU_PROFILES`,
`CRUCIBLE_EXECUTION_REGION`, `CRUCIBLE_DEFAULT_NAMESPACE` and
`CRUCIBLE_SPARK_SERVICE_ACCOUNT`; preserve an isolated kubeconfig/AWS role and
persistent local Postgres/controller ID; skip unrelated Databricks secret lookups
and `AWSCleanupVerticle`; use local Hub URLs for *all* CLI/UI operations; configure
remote CloudWatch logs explicitly. `s6e11-dev` derives `zipline-s6e11-dev` in
`CrucibleSubmitter.namespaceForTeam`. Ray reuses the Spark SA name in its own
namespace; this PR does not enroll that namespace in the shared compute chart.

## Identity, data and retention

The development SA trusts only its namespace/name/OIDC audience and receives
input-prefix read plus controller-prefix read and `controller/runs/` writes.
It has no S3 delete permission. The legacy wildcard Spark trust explicitly
excludes this SA. IMDSv2 hop limit 1 prevents normal pods from falling back to
node credentials. Existing node IAM supplies same-account private ECR pulls;
image publication is a separate owner action. Optional KMS and read-only Glue
ARN lists are empty by default; add only exact required keys/catalog/database/
tables after demo manifests identify them. No rows, schemas or Kaggle resources
are created here.

The local user assumes a new submitter role trusted by the configured principal;
use `aws eks update-kubeconfig --role-arn <submitter-role>` and that role's AWS
profile inside Docker. The role can describe this cluster, read/write the same
artifact prefixes and read this cluster's CloudWatch container log group. EKS
access maps it to `zipline:s6e11-dev`; RBAC permits RayJob CRUD only in the dev
namespace, observation there, and the cluster-wide **read-only** three-CRD cache
required by the existing Platform informer. No cluster-admin, production Hub
credentials, pod creation/exec, Secrets read or production namespace writes are
granted. Infrastructure/admin credentials are needed for cluster inventory and
the diagnostic exec commands below. Ray's autoscaler gets a namespace-only Role.

The verified existing curated, artifact and warehouse buckets have no versioning
or lifecycle policy. Artifact and warehouse resources belong to the resettable
orchestration state; its current config sets `bucket_force_destroy=true`.
The datasource module also uses `force_destroy=true` on raw/curated. Therefore a
new **opt-in retained training bucket and immutable ECR repository** belong to the
datasource state: force deletion disabled, `prevent_destroy`, S3 versioning,
AES256 encryption, public access blocked, no object/image expiration. Only
incomplete multipart uploads are aborted after seven days. This is not Object
Lock or a cross-region backup. Retained versions accumulate storage charges.

Demo uploads immutable inputs under the new retained bucket's `s6e11/input/`
prefix, and archives under its controller prefix. Existing curated data can be
read by explicitly choosing that bucket instead, but it lacks the new bucket's
retention protection. No training data prefix or contents exist yet. Set
`modelArtifactBaseUri` to the exact controller root in the manifest; Platform
appends `/runs/<workflow>/<step>/<attempt>/`, persists context, and writes progress,
checkpoints and reports there. Demo publishing credentials are separate; the
training/local submitter roles cannot overwrite source archives or delete evidence.

Platform's current IDs are workflow/step/attempt based, without a verified
persistent local-controller identity. Its local-profile owner must prove safe
adoption/cancellation across local DB resets. Before resetting a local DB, stop
submissions, reconcile/cancel named remote jobs, export `pg_dump` plus compiled
config hashes/run index, and preserve the controller prefix. Do not reuse IDs
while old jobs exist. Namespace isolation alone is not that proof. Remote workers
must never receive localhost callback URLs.

## Deadline, reset and rollback behavior

KubeRay checks both deadlines from RayJob `status.startTime`; active deadline
includes startup. Platform defaults pre-running deadline to min(900, timeout),
sets zero retries, and deletes the RayCluster 120 seconds after success/failure,
then the RayJob six hours later. [Upstream 1.7.0 controller](https://github.com/ray-project/kuberay/blob/v1.7.0/ray-operator/controllers/ray/rayjob_controller.go)
implements these independently of Hub availability. This still requires a healthy
operator/API and live validation, especially with the duplicate installations.

The Terraform controller cleanup now refuses reset if dev RayJobs or pods remain
and fails closed on inspection/auth errors. It runs before the GPU releases are
destroyed. Namespace `helm.sh/resource-policy: keep` preserves its identity on
Helm removal; it does not preserve jobs when EKS itself is deleted. Direct AWS
cluster deletion, targeted destroy that bypasses the guard, Helm uninstall or
turning the feature off can bypass the reset workflow: do not use those with active
jobs. Normal cleanup is deletion of a named RayJob, not namespace-wide deletion.

After explicit approval: first reconcile backend/config and operator ownership;
review full plans showing only intended changes; create retained storage/registry;
publish/verify image and archive through their owners; enable one profile and
namespace; validate admission/device registration; then authorize the bounded run.
Run `scripts/public-demo-gpu-preflight.sh` with the scoped submitter role, then
run it separately with `--admin` using infrastructure-reader credentials. It writes only a temp kubeconfig.
Never use a partial plan as the apply artifact. Re-plan immediately before approval.

Rollback: stop local submissions, cancel each named dev RayJob, verify RayClusters,
worker/head/submitter pods and profile NodeClaims disappear, then disable the local
profile and `gpu_training.enabled`. Keep retained bucket, registry, DB export and
compiled configurations. Check zero matching EC2 instances, not merely zero pods.
Do not remove CRD finalizers to force a busy node down. Keep the device plugin
until its GPU nodes are drained.

## Price and decision proposal — not approved

AWS Pricing `GetProducts` was refreshed on November 10 (effective November 1).
Whole Linux On-Demand instances: G6e **$1.861/h**, P4d **$21.95764/h**,
CPU head **$0.384/h** in Oregon. Virginia is $1.861, $21.957642 and $0.384/h:
no material savings. Both regions have 384-vCPU G and P On-Demand account quotas;
G Spot quota is zero, P Spot 384. No Spot interruption/resume validation exists,
so this implementation rejects Spot. Offerings in both regions do not prove
capacity. No capacity reservation/launch was attempted.

The API also returned a zero-dollar P4d Capacity Block OS line item; it is excluded
from prices because the reservation is purchased separately. [AWS Capacity Blocks](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-capacity-blocks.html)
support P4d in these regions, have reservation duration/start constraints and an
upfront charge; G6e is not listed. No block was quoted, reserved or purchased.
A region move would need a second EKS/VPC/operator/identity setup, copied images
and data, cross-region transfer and routing changes in the local launcher.
This PR does none of those; there is no demonstrated alternate-region opportunity.

Propose **one correctness run**, one G6e plus one control node, 1800-second job
limit including image pull/startup/evaluation, at most 900 seconds before Running.
Allow up to one billable hour for provisioning, the test and cleanup: compute
$2.245, plus a conservative $2.755 allowance for root EBS, public IPv4, retained
objects/registry and requests: **$5 proposed ceiling**. Keep upload/download under
10 GiB, same-region S3 access, no cross-region traffic. Existing EKS/control-plane
and observability costs are incremental-zero assumptions, not free resources.
Stored artifacts continue to cost money after scale-to-zero; review retained bytes.

Only after measuring that run, propose a separately approved one-P4d calibration
under the same 1800-second deadline/one-hour allocation envelope: compute
$22.34164 plus $7.65836 overhead allowance, **$30 proposed ceiling**. Combined
sequential proposal is $35, not authorization. These are supervised operational
budgets, not enforced dollar limits. Stop/cancel at the agreed time, verify node
termination and record actual billed duration; billing alerts are supplemental.
Do not promise a complete benchmark for this amount. The sole verified pilot was
one M4 Max; there is no measured four-GPU/eight-hour baseline or demonstrated
sixteen-GPU speedup. Use measured tokens/sec, startup and evaluation time to price
any full benchmark later.

## Unimplemented two-node extension

The capacity arithmetic and same-AZ gate are implemented but off. Before setting
`worker_nodes=2, multi_node_validated=true`: validate pinned EFA driver/device
plugin, actual EFA-capable network interfaces, self security-group traffic,
placement/capacity, libfabric/aws-ofi-nccl/NCCL versions and image settings.
Platform currently emits **no EFA resource request**; that contract needs an
additive owner change or a separately proven TCP-only path with measured costs.
Run two-host NCCL all-reduce and cancellation/failure tests, confirm 16 unique GPU
ranks and real network transport, then approve a new budget. EFA instance support
alone is insufficient; this PR does not claim distributed performance.

## Paid smoke commands prepared, not run

After approval, have Platform render the real RayJob using `integration.json`'s
resources and an actual immutable image/archive. Inspect/dry-run it before using
the local Hub to submit. Capture the exact name/UID, then use infrastructure
credentials for diagnostic exec (the local submitter deliberately lacks exec):

```bash
kubectl apply --dry-run=server -f reviewed-rayjob.yaml
kubectl get rayjobs,rayclusters,pods -n zipline-s6e11-dev
kubectl get nodes -l zipline.ai/nvidia-device-plugin=true \
  -o custom-columns='NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu'
# Set WORKER to the exact pod belonging to the recorded RayJob UID.
kubectl exec -n zipline-s6e11-dev "$WORKER" -c ray-worker -- nvidia-smi
kubectl exec -n zipline-s6e11-dev "$WORKER" -c ray-worker -- \
  python -c 'import torch; assert torch.cuda.is_available(); x=torch.ones(1024,device="cuda"); assert x.sum().item()==1024; print(torch.__version__,torch.version.cuda,torch.cuda.device_count(),torch.cuda.get_device_name(0))'
kubectl exec -n zipline-s6e11-dev "$WORKER" -c ray-worker -- df -h /dev/shm /tmp
```

For one P4d only, the image owner supplies a pinned `nccl-tests` binary. This
single-process smoke probes all eight local devices without claiming multi-node
transport; run through the approved worker image/entrypoint or admin exec:

```bash
kubectl exec -n zipline-s6e11-dev "$WORKER" -c ray-worker -- \
  /opt/nccl-tests/build/all_reduce_perf -b 8M -e 64M -f 2 -g 8 -n 5
```

Also run one deliberately over-deadline tiny RayJob and one explicit cancel,
with Hub stopped during the deadline test. Confirm failure/cleanup is driven by
KubeRay, collect S3 progress/report/checkpoint evidence with the submitter role,
and verify writes outside the controller run prefix are denied using IAM simulation
before any destructive probe. Test the actual image's S3 client uses IRSA on head
and worker. No real GPU, NCCL, signed-download, cancellation or outage test has run.

```bash
# Only the recorded job; save its status/report first.
kubectl delete rayjob "$RAYJOB" -n zipline-s6e11-dev --wait=true
kubectl get rayclusters,pods -n zipline-s6e11-dev
kubectl get nodeclaims -l karpenter.sh/nodepool=s6e11-l40s-worker
# An admin must also check EC2 instance termination for both profile pools.
```

Validate negative admission cases after deployment: a 21601-second deadline,
missing DeleteCluster rules, wrong SA/profile, GPU-free worker, oversized RAM,
extra worker, and a second simultaneous RayJob must all be rejected. A valid
Platform-rendered fixture must pass. Server-side dry-run of the policy itself
checks API acceptance, not these runtime enforcement outcomes.
