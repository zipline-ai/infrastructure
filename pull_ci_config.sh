#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<EOF
Usage: $0 <aws|azure|gcp>

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

download_optional_gcs_object() {
  local bucket="$1"
  local prefix="$2"
  local name="$3"
  local dest="$4"
  local key="${prefix:+${prefix}/}${name}"

  if gcloud storage ls "gs://${bucket}/${key}" >/dev/null 2>&1; then
    gcloud storage cp "gs://${bucket}/${key}" "${dest}" --quiet
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

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# GCP shares the AWS config bucket (zipline-crucible-vars) by default, with
# a gcp/ prefix so the keys don't collide — matches plan §5.1.
bucket="${CRUCIBLE_CONFIG_BUCKET:-zipline-crucible-ci-vars}"
wrapper_key="${CRUCIBLE_CONFIG_KEY:-gcp/zipline-orchestration/ci.auto.tfvars.json}"
config_prefix="${wrapper_key%/*}"
if [ "${config_prefix}" = "${wrapper_key}" ]; then
  config_prefix=""
fi
backend_key="${config_prefix:+${config_prefix}/}backend.hcl"
root_dest="${CRUCIBLE_CONFIG_ROOT:-${repo_root}/gcp/zipline-orchestration}"

mkdir -p "${root_dest}"

tmp_backend="$(mktemp "${root_dest}/backend.hcl.XXXXXX")"
tmp_tfvars="$(mktemp "${root_dest}/ci.auto.tfvars.json.XXXXXX")"
trap 'rm -f "${tmp_backend:-}" "${tmp_tfvars:-}"' EXIT

gcloud storage cp "gs://${bucket}/${backend_key}" "${tmp_backend}" --quiet
gcloud storage cp "gs://${bucket}/${wrapper_key}" "${tmp_tfvars}" --quiet
require_grouped_tfvars gcp "${tmp_tfvars}"
clean_ignored_config_files "${root_dest}"
mv "${tmp_backend}" "${root_dest}/backend.hcl"
mv "${tmp_tfvars}" "${root_dest}/ci.auto.tfvars.json"
trap - EXIT

download_optional_gcs_object "${bucket}" "${config_prefix}" "dns-provider.tf" "${root_dest}/dns-provider.tf"
download_optional_gcs_object "${bucket}" "${config_prefix}" "dns.auto.tfvars.json" "${root_dest}/dns.auto.tfvars.json"
download_optional_gcs_object "${bucket}" "${config_prefix}" ".terraform.lock.hcl" "${root_dest}/.terraform.lock.hcl"

cat <<EOF
Pulled GCP Crucible orchestration config from:
  gs://${bucket}/${config_prefix}

Local files are intentionally ignored by git:
  ${root_dest}/backend.hcl
  ${root_dest}/ci.auto.tfvars.json
EOF