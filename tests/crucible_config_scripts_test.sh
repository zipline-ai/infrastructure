#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "${test_root}"' EXIT

remote_root="${test_root}/remote"
local_root="${test_root}/local"
mkdir -p "${remote_root}/zipline-orchestration" "${local_root}"

printf 'bucket = "test-state"\n' >"${remote_root}/zipline-orchestration/backend.hcl"
printf '{"orchestration":{},"aws":{}}\n' >"${remote_root}/zipline-orchestration/crucible.auto.tfvars.json"
printf 'resource "aws_s3_bucket_policy" "artifact_access" {}\n' >"${remote_root}/zipline-orchestration/artifact-access.tf"

export AWS_MOCK_ROOT="${remote_root}"
export CRUCIBLE_CONFIG_ROOT="${local_root}"
export PATH="${repo_root}/tests/fixtures:${PATH}"

"${repo_root}/pull_crucible_config.sh" aws >/dev/null
cmp "${remote_root}/zipline-orchestration/artifact-access.tf" "${local_root}/artifact-access.tf"

rm "${remote_root}/zipline-orchestration/artifact-access.tf"
printf 'stale\n' >"${local_root}/artifact-access.tf"
"${repo_root}/pull_crucible_config.sh" aws >/dev/null
test ! -e "${local_root}/artifact-access.tf"

printf 'resource "aws_s3_bucket_policy" "artifact_access" {}\n' >"${local_root}/artifact-access.tf"
"${repo_root}/push_crucible_config.sh" aws
cmp "${local_root}/artifact-access.tf" "${remote_root}/zipline-orchestration/artifact-access.tf"
