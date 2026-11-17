#!/usr/bin/env bash
set -euo pipefail

# Uploads the git-ignored infratest orchestration config (backend + tfvars) from
# <cloud>/zipline-orchestration/. Run this after editing the local config so the
# nightly e2e workflow picks it up. Minimal mirror of push_crucible_config.sh.
# Usage: push_infratest_config.sh [aws|gcp]   (default: aws)

cloud="${1:-aws}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${repo_root}/infratest_config_common.sh"
src="${INFRATEST_CONFIG_ROOT:-${repo_root}/${cloud}/zipline-orchestration}"

for f in "${config_files[@]}"; do
  [ -f "${src}/${f}" ] || { echo "Missing ${src}/${f}" >&2; exit 1; }
  copy_config "${src}/${f}" "${config_uri}/${f}"
done

echo "Pushed ${cloud} infratest config to ${config_uri}."
