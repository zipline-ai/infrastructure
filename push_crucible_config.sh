#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<EOF
Usage: $0 <aws|azure>

Uploads Crucible orchestration config for the selected cloud from the
git-ignored local files used by that cloud's Terraform wrapper.
EOF
}

require_file() {
  if [ ! -f "$1" ]; then
    echo "Missing $1" >&2
    exit 1
  fi
}

require_grouped_tfvars() {
  local cloud="$1"
  local file="$2"

  require_file "${file}"

  if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required to validate Crucible tfvars." >&2
    exit 1
  fi

  if ! jq -e --arg cloud "${cloud}" 'has("orchestration") and has($cloud)' "${file}" >/dev/null; then
    echo "${file} must contain top-level orchestration and ${cloud} objects. Run pull_crucible_config.sh ${cloud} first." >&2
    exit 1
  fi
}

if [ "$#" -ne 1 ]; then
  usage
  exit 1
fi

cloud="$1"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "${cloud}" in
  aws)
    bucket="${CRUCIBLE_CONFIG_BUCKET:-zipline-crucible-vars}"
    wrapper_key="${CRUCIBLE_CONFIG_KEY:-zipline-orchestration/crucible.auto.tfvars.json}"
    wrapper_file="${CRUCIBLE_CONFIG_ROOT:-${repo_root}/aws/zipline-orchestration}/crucible.auto.tfvars.json"

    require_grouped_tfvars aws "${wrapper_file}"

    aws s3 cp "${wrapper_file}" "s3://${bucket}/${wrapper_key}"
    ;;
  azure)
    storage_account="${AZURE_CONFIG_STORAGE_ACCOUNT:-ziplineai2}"
    container="${AZURE_CONFIG_CONTAINER:-dev-zipline-vars}"
    prefix="${AZURE_CONFIG_PREFIX:-crucible-azure/zipline-orchestration}"
    src="${CRUCIBLE_CONFIG_DIR:-${repo_root}/azure/zipline-orchestration}"

    require_file "${src}/backend.hcl"
    require_grouped_tfvars azure "${src}/crucible.auto.tfvars.json"

    az storage blob upload \
      --account-name "${storage_account}" \
      --container-name "${container}" \
      --name "${prefix}/backend.hcl" \
      --file "${src}/backend.hcl" \
      --auth-mode login \
      --overwrite true \
      --output none

    az storage blob upload \
      --account-name "${storage_account}" \
      --container-name "${container}" \
      --name "${prefix}/crucible.auto.tfvars.json" \
      --file "${src}/crucible.auto.tfvars.json" \
      --auth-mode login \
      --overwrite true \
      --output none
    ;;
  *)
    usage
    exit 1
    ;;
esac
