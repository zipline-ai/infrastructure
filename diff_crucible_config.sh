#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<EOF
Usage: $0 <aws|azure>

Downloads Crucible orchestration config for the selected cloud into a temp
directory and diffs it against the git-ignored config files currently present
locally.
EOF
}

copy_ignored_config_files() {
  local src="$1"
  local dest="$2"

  if [ ! -d "${src}" ]; then
    return
  fi

  find "${src}" -mindepth 1 -maxdepth 1 \( \
    -name 'backend.hcl' -o \
    -name '.terraform.lock.hcl' -o \
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

if [ "$#" -ne 1 ]; then
  usage
  exit 1
fi

cloud="$1"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp_root="$(mktemp -d)"
trap 'rm -rf "${tmp_root}"' EXIT

current_snapshot="${tmp_root}/current"
remote_snapshot="${tmp_root}/remote"
mkdir -p "${current_snapshot}" "${remote_snapshot}"

case "${cloud}" in
  aws)
    current_root="${CRUCIBLE_CONFIG_ROOT:-${repo_root}/aws/zipline-orchestration}"
    copy_ignored_config_files "${current_root}" "${current_snapshot}"
    CRUCIBLE_CONFIG_ROOT="${remote_snapshot}" "${repo_root}/pull_crucible_config.sh" aws >/dev/null
    ;;
  azure)
    current_root="${CRUCIBLE_CONFIG_DIR:-${repo_root}/azure/zipline-orchestration}"
    copy_ignored_config_files "${current_root}" "${current_snapshot}"
    CRUCIBLE_CONFIG_DIR="${remote_snapshot}" "${repo_root}/pull_crucible_config.sh" azure >/dev/null
    ;;
  *)
    usage
    exit 1
    ;;
esac

set +e
diff -ru "${current_snapshot}" "${remote_snapshot}"
status=$?
set -e

if [ "${status}" -eq 0 ]; then
  echo "No differences between local ${cloud} Crucible config and remote."
fi

exit "${status}"
