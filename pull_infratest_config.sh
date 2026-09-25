#!/usr/bin/env bash
set -euo pipefail

# Downloads the git-ignored infratest orchestration config (backend + tfvars,
# which carry secrets) from S3 into aws/zipline-orchestration/ for tofu.
# Minimal mirror of pull_crucible_config.sh, used by the nightly AWS e2e workflow.

bucket="${INFRATEST_CONFIG_BUCKET:-infratest-opentofu-state}"
prefix="${INFRATEST_CONFIG_PREFIX:-config}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dest="${INFRATEST_CONFIG_ROOT:-${repo_root}/aws/zipline-orchestration}"

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

for f in backend.hcl infratest.auto.tfvars .terraform.lock.hcl; do
  aws s3 cp "s3://${bucket}/${prefix}/${f}" "${dest}/${f}"
done

echo "Pulled infratest config from s3://${bucket}/${prefix} into ${dest} (git-ignored)."
