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
    return 1
  fi

  if ! jq -e --arg cloud "${cloud}" 'has("orchestration") and has($cloud)' "${file}" >/dev/null; then
    echo "${file} must contain top-level orchestration and ${cloud} objects." >&2
    return 1
  fi
}

download_optional_s3_object() {
  local bucket="$1"
  local prefix="$2"
  local name="$3"
  local dest="$4"
  local key="${prefix:+${prefix}/}${name}"

  if aws s3 ls "s3://${bucket}/${key}" >/dev/null 2>&1; then
    aws s3 cp "s3://${bucket}/${key}" "${dest}"
  else
    rm -f "${dest}"
  fi
}

download_optional_azure_blob() {
  local storage_account="$1"
  local container="$2"
  local name="$3"
  local dest="$4"

  if [ "$(az storage blob exists \
    --account-name "${storage_account}" \
    --container-name "${container}" \
    --name "${name}" \
    --auth-mode login \
    --query exists \
    --output tsv)" = "true" ]; then
    az storage blob download \
      --account-name "${storage_account}" \
      --container-name "${container}" \
      --name "${name}" \
      --file "${dest}" \
      --auth-mode login \
      --overwrite true \
      --output none
  else
    rm -f "${dest}"
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
    config_prefix="${wrapper_key%/*}"
    if [ "${config_prefix}" = "${wrapper_key}" ]; then
      config_prefix=""
    fi
    backend_key="${config_prefix:+${config_prefix}/}backend.hcl"
    root_dest="${CRUCIBLE_CONFIG_ROOT:-${repo_root}/aws/zipline-orchestration}"

    mkdir -p "${root_dest}"

    tmp_backend="$(mktemp "${root_dest}/backend.hcl.XXXXXX")"
    tmp_tfvars="$(mktemp "${root_dest}/crucible.auto.tfvars.json.XXXXXX")"
    trap 'rm -f "${tmp_backend:-}" "${tmp_tfvars:-}"' EXIT

    aws s3 cp "s3://${bucket}/${backend_key}" "${tmp_backend}"
    aws s3 cp "s3://${bucket}/${wrapper_key}" "${tmp_tfvars}"
    require_grouped_tfvars aws "${tmp_tfvars}"
    mv "${tmp_backend}" "${root_dest}/backend.hcl"
    mv "${tmp_tfvars}" "${root_dest}/crucible.auto.tfvars.json"
    trap - EXIT

    download_optional_s3_object "${bucket}" "${config_prefix}" "dns-provider.tf" "${root_dest}/dns-provider.tf"
    download_optional_s3_object "${bucket}" "${config_prefix}" "dns.auto.tfvars.json" "${root_dest}/dns.auto.tfvars.json"

    cat <<EOF
Pulled AWS Crucible orchestration config from:
  s3://${bucket}/${config_prefix}

Local files are intentionally ignored by git:
  ${root_dest}/backend.hcl
  ${root_dest}/crucible.auto.tfvars.json
EOF
    ;;
  azure)
    storage_account="${AZURE_CONFIG_STORAGE_ACCOUNT:-ziplineai2}"
    container="${AZURE_CONFIG_CONTAINER:-dev-zipline-vars}"
    prefix="${AZURE_CONFIG_PREFIX:-crucible-azure/zipline-orchestration}"
    dest="${CRUCIBLE_CONFIG_DIR:-${repo_root}/azure/zipline-orchestration}"

    mkdir -p "${dest}"

    tmp_backend="$(mktemp "${dest}/backend.hcl.XXXXXX")"
    tmp_tfvars="$(mktemp "${dest}/crucible.auto.tfvars.json.XXXXXX")"
    trap 'rm -f "${tmp_backend:-}" "${tmp_tfvars:-}"' EXIT

    az storage blob download \
      --account-name "${storage_account}" \
      --container-name "${container}" \
      --name "${prefix}/backend.hcl" \
      --file "${tmp_backend}" \
      --auth-mode login \
      --overwrite true \
      --output none

    az storage blob download \
      --account-name "${storage_account}" \
      --container-name "${container}" \
      --name "${prefix}/crucible.auto.tfvars.json" \
      --file "${tmp_tfvars}" \
      --auth-mode login \
      --overwrite true \
      --output none

    require_grouped_tfvars azure "${tmp_tfvars}"
    mv "${tmp_backend}" "${dest}/backend.hcl"
    mv "${tmp_tfvars}" "${dest}/crucible.auto.tfvars.json"
    trap - EXIT

    download_optional_azure_blob "${storage_account}" "${container}" "${prefix}/dns-provider.tf" "${dest}/dns-provider.tf"
    download_optional_azure_blob "${storage_account}" "${container}" "${prefix}/dns.auto.tfvars.json" "${dest}/dns.auto.tfvars.json"

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
