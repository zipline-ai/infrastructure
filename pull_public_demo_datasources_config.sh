#!/usr/bin/env bash
set -euo pipefail

# Downloads the git-ignored public-demo datasource config (backend + tfvars)
# from S3 into aws/public-demo-datasources/ for OpenTofu.

bucket="${PUBLIC_DEMO_CONFIG_BUCKET:-zipline-public-demo-opentofu-state}"
prefix="${PUBLIC_DEMO_DATASOURCES_CONFIG_PREFIX:-config/datasources}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dest="${PUBLIC_DEMO_DATASOURCES_CONFIG_ROOT:-${repo_root}/aws/public-demo-datasources}"

clean_ignored_config_files() {
  local dest="$1"

  find "${dest}" -mindepth 1 -maxdepth 1 \( \
    -name 'backend.hcl' -o \
    -name '.terraform.lock.hcl' -o \
    -name '.terraform' -o \
    -name '*.tfvars' -o \
    -name '*.tfvars.json' -o \
    -name '*.auto.tfvars' -o \
    -name '*.auto.tfvars.json' -o \
    -name 'current-helm-values.*' -o \
    -name 'dns-provider.tf' -o \
    -name 'cloudflare.tf' -o \
    -name 'github.tf' -o \
    -name '.crucible-config' -o \
    -name 'crucible-config' \
  \) -exec rm -rf {} +
}

mkdir -p "${dest}"
clean_ignored_config_files "${dest}"

for f in backend.hcl public-demo-datasources.auto.tfvars .terraform.lock.hcl; do
  aws s3 cp "s3://${bucket}/${prefix}/${f}" "${dest}/${f}"
done

echo "Pulled public-demo datasource config from s3://${bucket}/${prefix} into ${dest} (git-ignored)."
