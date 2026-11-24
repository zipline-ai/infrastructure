#!/usr/bin/env bash
set -euo pipefail

# Downloads the git-ignored infratest orchestration config (backend + tfvars,
# which carry secrets) into <cloud>/zipline-orchestration/ for tofu.
# Minimal mirror of pull_crucible_config.sh, used by the nightly e2e workflows.
# Usage: pull_infratest_config.sh [aws|gcp]   (default: aws)

cloud="${1:-aws}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${repo_root}/infratest_config_common.sh"
dest="${INFRATEST_CONFIG_ROOT:-${repo_root}/${cloud}/zipline-orchestration}"

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

for f in "${config_files[@]}"; do
  copy_config "${config_uri}/${f}" "${dest}/${f}"
done

echo "Pulled ${cloud} infratest config from ${config_uri} into ${dest} (git-ignored)."
