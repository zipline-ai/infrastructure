#!/usr/bin/env bash
set -euo pipefail

# Uploads the git-ignored public-demo datasource config (backend + tfvars)
# from aws/public-demo-datasources/ to S3.

bucket="${PUBLIC_DEMO_CONFIG_BUCKET:-zipline-public-demo-opentofu-state}"
prefix="${PUBLIC_DEMO_DATASOURCES_CONFIG_PREFIX:-config/datasources}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="${PUBLIC_DEMO_DATASOURCES_CONFIG_ROOT:-${repo_root}/aws/public-demo-datasources}"

for f in backend.hcl public-demo-datasources.auto.tfvars; do
  [ -f "${src}/${f}" ] || { echo "Missing ${src}/${f}" >&2; exit 1; }
  aws s3 cp "${src}/${f}" "s3://${bucket}/${prefix}/${f}"
done

echo "Pushed public-demo datasource config to s3://${bucket}/${prefix}."
