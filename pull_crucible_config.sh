#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<EOF
Usage: $0 <aws|azure>

Downloads Crucible orchestration config for the selected cloud into the
git-ignored local files used by that cloud's Terraform wrapper.
EOF
}

require_grouped_tfvars() {
  local cloud="$1"
  local file="$2"

  if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required to validate Crucible tfvars." >&2
    exit 1
  fi

  if ! jq -e --arg cloud "${cloud}" 'has("orchestration") and has($cloud)' "${file}" >/dev/null; then
    echo "${file} must contain top-level orchestration and ${cloud} objects." >&2
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
    root_dest="${CRUCIBLE_CONFIG_ROOT:-${repo_root}/aws/zipline-orchestration}"

    mkdir -p "${root_dest}"

    aws s3 cp "s3://${bucket}/${wrapper_key}" "${root_dest}/crucible.auto.tfvars.json"
    require_grouped_tfvars aws "${root_dest}/crucible.auto.tfvars.json"

    cat <<EOF
Pulled AWS Crucible orchestration config from:
  s3://${bucket}/${wrapper_key}

Local file is intentionally ignored by git:
  ${root_dest}/crucible.auto.tfvars.json
EOF
    ;;
  azure)
    storage_account="${AZURE_CONFIG_STORAGE_ACCOUNT:-ziplineai2}"
    container="${AZURE_CONFIG_CONTAINER:-dev-zipline-vars}"
    prefix="${AZURE_CONFIG_PREFIX:-crucible-azure/zipline-orchestration}"
    dest="${CRUCIBLE_CONFIG_DIR:-${repo_root}/azure/zipline-orchestration}"

    mkdir -p "${dest}"

    az storage blob download \
      --account-name "${storage_account}" \
      --container-name "${container}" \
      --name "${prefix}/backend.hcl" \
      --file "${dest}/backend.hcl" \
      --auth-mode login \
      --overwrite true \
      --output none

    az storage blob download \
      --account-name "${storage_account}" \
      --container-name "${container}" \
      --name "${prefix}/crucible.auto.tfvars.json" \
      --file "${dest}/crucible.auto.tfvars.json" \
      --auth-mode login \
      --overwrite true \
      --output none

    require_grouped_tfvars azure "${dest}/crucible.auto.tfvars.json"

    cat <<EOF
Pulled Azure Crucible orchestration config from:
  storage account: ${storage_account}
  container:       ${container}
  prefix:          ${prefix}

Local files are intentionally ignored by git:
  ${dest}/backend.hcl
  ${dest}/crucible.auto.tfvars.json
EOF
    ;;
  *)
    usage
    exit 1
    ;;
esac
