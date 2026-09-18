#!/usr/bin/env bash
set -euo pipefail

# Downloads the git-ignored public-demo orchestration config (backend + tfvars)
# from S3 into aws/zipline-orchestration/ for OpenTofu.

bucket="${PUBLIC_DEMO_CONFIG_BUCKET:-zipline-public-demo-opentofu-state}"
prefix="${PUBLIC_DEMO_CONFIG_PREFIX:-config/orchestration}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dest="${PUBLIC_DEMO_CONFIG_ROOT:-${repo_root}/aws/zipline-orchestration}"

clean_ignored_config_files() {
  local dest="$1"

  find "${dest}" -mindepth 1 -maxdepth 1 \( \
    -name 'backend.hcl' -o \
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

for f in backend.hcl public-demo.auto.tfvars dns-provider.tf dns.auto.tfvars.json; do
  aws s3 cp "s3://${bucket}/${prefix}/${f}" "${dest}/${f}"
done

echo "Pulled public-demo orchestration config from s3://${bucket}/${prefix} into ${dest} (git-ignored)."
