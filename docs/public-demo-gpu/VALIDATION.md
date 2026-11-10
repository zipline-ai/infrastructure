# Validation evidence — 2026-11-10

Base: infrastructure `d392916` (`origin/main` when the isolated worktree was
created). Branch: `codex/public-demo-gpu-training`. Platform PR #1461 inspected
read-only at `c883f570745449e883417ef66a5bb2ee35231eee`. Original workspaces,
Platform launcher/trainer and secret-bearing inputs were not edited.

| Check | Result |
|---|---|
| Full repository Python suite | **43 passed** (`python -m unittest discover -s tests`, 6.2 seconds) |
| New GPU tests | Seven tests with subcases: disabled CPU compatibility, hardware/one-two node limits, contradictory selectors, namespace/RBAC/admission render, actual plugin values, fail-closed reset guard, identity/retention scope |
| Existing CPU tests | Corrected three stale expected sets to include the already-existing `ray-control`/`ray-worker`; no CPU pool implementation change |
| HCL formatting | Changed Terraform and example inputs pass `tofu fmt -check` |
| Orchestration module | `tofu validate`: valid, with existing deployment provider lockfile |
| Datasource module | `tofu validate`: valid, with existing deployment provider lockfile |
| Helm | Both local charts pass `helm lint`; one/two-node classes/pools render as valid YAML |
| NVIDIA chart | Pinned 0.17.1 rendered with actual Terraform-derived values: one device-plugin DaemonSet, no NFD/GFD dependency, correct selectors/tolerations; dormant upstream MPS companion requires an unset node label |
| Kubernetes API | Final ValidatingAdmissionPolicy and binding accepted by `kubectl create --dry-run=server`; nothing persisted |
| Shell | Preflight `bash -n`; reset guard executed with stubbed AWS/kubectl for absent namespace, empty namespace, active RayJob, remaining pod, authentication failure and inspection failure |
| Diff | `git diff --check` clean; changes limited to optional GPU/namespace/IAM/storage, reset interlock, chart class list support and tests/docs |

OpenTofu 1.12.7 was used. Provider processes need local IPC permissions unavailable
in the restricted shell; final module validations ran successfully with the same
reviewed elevated execution used for read-only AWS access. No provider versions
are changed in this PR. Temporary Python environment: PyYAML, python-hcl2 7.3.1,
boto3. No dependency files or user tool-version files were changed.

## Plan coverage

Both existing S3 backends were verified from local initialization metadata before
initializing the isolated worktree. Bucket `zipline-public-demo-opentofu-state`,
region `us-west-2`, workspace `default`; keys are
`state/orchestration/terraform.tfstate` and `state/datasources/terraform.tfstate`.
No alternate or local state was silently substituted. `-lock=false` plans read
state without writing a lock or state; refresh results were not applied.

- Targeted compute/IAM preview: **9 add, 1 update, 0 destroy**. The update excludes
  the new development SA from the old wildcard Spark role trust. New resources
  are the two roles/four policies, access entry and two Helm releases. Exact
  addresses are in `plan-summary.json`.
- Targeted retained storage preview: **6 add, 0 update, 0 destroy**: bucket,
  versioning, public-access block, encryption, incomplete-upload lifecycle and
  immutable ECR repository. No existing datasource modifications.
- Full orchestration plan **did not succeed**: Cloudflare authentication is not
  available, and the required Docker Hub token was deliberately removed from
  the review input copy. Neither was substituted or displayed. The namespace
  release depends on the shared orchestration module and is excluded from the
  targeted preview; namespace/RBAC/quota/admission were Helm-rendered separately.
  The reset guard likewise is not covered by that targeted preview.
- JSON export of the partial orchestration plan failed on the pre-existing
  Cloudflare `include_shadow_metadata` state attribute with the existing lockfile.
  The committed summary contains only addresses/actions extracted from the
  successful text plan; no state or secret-bearing plan is committed.
- Datasource tfvars are stale/missing a required field. The targeted storage plan
  used explicit non-secret region/storage identifiers and only new resources;
  it is not evidence that a broad datasource plan is safe.

The partial binary plans/logs remain private temporary files (mode 0600), not PR
artifacts or apply instructions. Full plans with authorized credentials and
reconciled inputs must show no unrelated/destructive changes before deployment.

## Live checks versus deferred checks

Performed: STS identity, EKS version/subnets, EC2 instance metadata/offerings,
regional quotas/running GPU inventory, Pricing API, SSM NVIDIA AMI metadata,
Helm/operator/DaemonSet inventory, allocatable GPU inventory, RayJob deadline CRD
inspection, bucket encryption/versioning/lifecycle, and admission-policy API dry-run.

Deferred until approval: actual admission rejection/acceptance against rendered
Platform jobs, GPU allocation/plugin registration, CUDA/PyTorch/NCCL execution,
IRSA S3 upload/download, exact driver/runtime compatibility, image-pull footprint,
CPU/DaemonSet overhead, cancellation, Hub-offline deadline cleanup and node
termination. The exact checks are in the runbook. The two-node EFA/NCCL path is
not implemented or validated. No availability guarantee or benchmark speedup is
claimed.
