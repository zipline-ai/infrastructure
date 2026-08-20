#!/usr/bin/env bash
set -euo pipefail

# Uploads the git-ignored public-demo orchestration config (backend + tfvars)
# from aws/zipline-orchestration/ to S3.

bucket="${PUBLIC_DEMO_CONFIG_BUCKET:-zipline-public-demo-opentofu-state}"
prefix="${PUBLIC_DEMO_CONFIG_PREFIX:-config/orchestration}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="${PUBLIC_DEMO_CONFIG_ROOT:-${repo_root}/aws/zipline-orchestration}"

for f in backend.hcl public-demo.auto.tfvars; do
  [ -f "${src}/${f}" ] || { echo "Missing ${src}/${f}" >&2; exit 1; }
  aws s3 cp "${src}/${f}" "s3://${bucket}/${prefix}/${f}"
done

echo "Pushed public-demo orchestration config to s3://${bucket}/${prefix}."
