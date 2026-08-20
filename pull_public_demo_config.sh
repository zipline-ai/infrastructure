#!/usr/bin/env bash
set -euo pipefail

# Downloads the git-ignored public-demo orchestration config (backend + tfvars)
# from S3 into aws/zipline-orchestration/ for OpenTofu.

bucket="${PUBLIC_DEMO_CONFIG_BUCKET:-zipline-public-demo-opentofu-state}"
prefix="${PUBLIC_DEMO_CONFIG_PREFIX:-config/orchestration}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dest="${PUBLIC_DEMO_CONFIG_ROOT:-${repo_root}/aws/zipline-orchestration}"

mkdir -p "${dest}"
for f in backend.hcl public-demo.auto.tfvars; do
  aws s3 cp "s3://${bucket}/${prefix}/${f}" "${dest}/${f}"
done

echo "Pulled public-demo orchestration config from s3://${bucket}/${prefix} into ${dest} (git-ignored)."
