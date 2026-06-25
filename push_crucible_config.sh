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

if [ "$#" -ne 1 ]; then
  usage
  exit 1
fi

cloud="$1"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "${cloud}" in
  aws)
    bucket="${CRUCIBLE_CONFIG_BUCKET:-zipline-crucible-vars}"
    src="${CRUCIBLE_CONFIG_DIR:-${repo_root}/aws/zipline-orchestration/.crucible-config/raw}"

    require_file "${src}/terraform.tfvars"
    require_file "${src}/github.tf"
    require_file "${src}/cloudflare.tf"
    require_file "${src}/.terraform.lock.hcl"

    aws s3 cp "${src}/terraform.tfvars" "s3://${bucket}/terraform.tfvars"
    aws s3 cp "${src}/github.tf" "s3://${bucket}/github.tf"
    aws s3 cp "${src}/cloudflare.tf" "s3://${bucket}/cloudflare.tf"
    aws s3 cp "${src}/.terraform.lock.hcl" "s3://${bucket}/.terraform.lock.hcl"
    aws s3 cp "${src}/crucible-config" "s3://${bucket}/crucible-config" --recursive
    ;;
  azure)
    storage_account="${AZURE_CONFIG_STORAGE_ACCOUNT:-ziplineai2}"
    container="${AZURE_CONFIG_CONTAINER:-dev-zipline-vars}"
    prefix="${AZURE_CONFIG_PREFIX:-crucible-azure/zipline-orchestration}"
    src="${CRUCIBLE_CONFIG_DIR:-${repo_root}/azure/zipline-orchestration}"

    require_file "${src}/backend.hcl"
    require_file "${src}/crucible.auto.tfvars.json"

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
