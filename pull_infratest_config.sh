#!/usr/bin/env bash
set -euo pipefail

# Downloads the git-ignored infratest orchestration config (backend + tfvars,
# which carry secrets) from S3 into aws/zipline-orchestration/ for tofu.
# Minimal mirror of pull_crucible_config.sh, used by the nightly AWS e2e workflow.

bucket="${INFRATEST_CONFIG_BUCKET:-infratest-opentofu-state}"
prefix="${INFRATEST_CONFIG_PREFIX:-config}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dest="${INFRATEST_CONFIG_ROOT:-${repo_root}/aws/zipline-orchestration}"

mkdir -p "${dest}"
for f in backend.hcl infratest.auto.tfvars; do
  aws s3 cp "s3://${bucket}/${prefix}/${f}" "${dest}/${f}"
done

echo "Pulled infratest config from s3://${bucket}/${prefix} into ${dest} (git-ignored)."
