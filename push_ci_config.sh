#!/usr/bin/env bash
set -euo pipefail

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

upload_optional_gcs_object() {
  local bucket="$1"
  local prefix="$2"
  local file="$3"
  local name="$4"
  local key="${prefix:+${prefix}/}${name}"

  if [ -f "${file}" ]; then
    gcloud storage cp "${file}" "gs://${bucket}/${key}" --quiet
  fi
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bucket="${CRUCIBLE_CONFIG_BUCKET:-zipline-crucible-ci-vars}"
wrapper_key="${CRUCIBLE_CONFIG_KEY:-gcp/zipline-orchestration/crucible.auto.tfvars.json}"
config_prefix="${wrapper_key%/*}"
if [ "${config_prefix}" = "${wrapper_key}" ]; then
  config_prefix=""
fi
backend_key="${config_prefix:+${config_prefix}/}backend.hcl"
wrapper_root="${CRUCIBLE_CONFIG_ROOT:-${repo_root}/gcp/zipline-orchestration}"
backend_file="${wrapper_root}/backend.hcl"
wrapper_file="${wrapper_root}/ci.auto.tfvars.json"

require_file "${backend_file}"
require_grouped_tfvars gcp "${wrapper_file}"

gcloud storage cp "${backend_file}" "gs://${bucket}/${backend_key}" --quiet
gcloud storage cp "${wrapper_file}" "gs://${bucket}/${wrapper_key}" --quiet
upload_optional_gcs_object "${bucket}" "${config_prefix}" "${wrapper_root}/dns-provider.tf" "dns-provider.tf"
upload_optional_gcs_object "${bucket}" "${config_prefix}" "${wrapper_root}/dns.auto.tfvars.json" "dns.auto.tfvars.json"
upload_optional_gcs_object "${bucket}" "${config_prefix}" "${wrapper_root}/.terraform.lock.hcl" ".terraform.lock.hcl"
