#!/usr/bin/env bash
set -euo pipefail

# Downloads public-demo orchestration config into a temp directory and diffs it
# against the git-ignored config files currently present locally.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
current_root="${PUBLIC_DEMO_CONFIG_ROOT:-${repo_root}/aws/zipline-orchestration}"
tmp_root="$(mktemp -d)"
trap 'rm -rf "${tmp_root}"' EXIT

current_snapshot="${tmp_root}/current"
remote_snapshot="${tmp_root}/remote"
mkdir -p "${current_snapshot}" "${remote_snapshot}"

copy_ignored_config_files() {
  local src="$1"
  local dest="$2"

  if [ ! -d "${src}" ]; then
    return
  fi

  find "${src}" -mindepth 1 -maxdepth 1 \( \
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
  \) -exec cp -R {} "${dest}/" \;
}

copy_ignored_config_files "${current_root}" "${current_snapshot}"
PUBLIC_DEMO_CONFIG_ROOT="${remote_snapshot}" "${repo_root}/pull_public_demo_config.sh" >/dev/null

set +e
diff -ru "${current_snapshot}" "${remote_snapshot}"
status=$?
set -e

if [ "${status}" -eq 0 ]; then
  echo "No differences between local public-demo orchestration config and remote."
fi

exit "${status}"
