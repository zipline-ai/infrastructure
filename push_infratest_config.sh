#!/usr/bin/env bash
set -euo pipefail

# Uploads the git-ignored infratest orchestration config (backend + tfvars) from
# aws/zipline-orchestration/ to S3. Run this after editing the local config so the
# nightly AWS e2e workflow picks it up. Minimal mirror of push_crucible_config.sh.

bucket="${INFRATEST_CONFIG_BUCKET:-infratest-opentofu-state}"
prefix="${INFRATEST_CONFIG_PREFIX:-config}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="${INFRATEST_CONFIG_ROOT:-${repo_root}/aws/zipline-orchestration}"

for f in backend.hcl infratest.auto.tfvars; do
  [ -f "${src}/${f}" ] || { echo "Missing ${src}/${f}" >&2; exit 1; }
  aws s3 cp "${src}/${f}" "s3://${bucket}/${prefix}/${f}"
done

echo "Pushed infratest config to s3://${bucket}/${prefix}."
