#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<EOF
Usage: $0 <aws|azure>

Downloads Crucible orchestration config for the selected cloud into the
git-ignored local files used by that cloud's Terraform wrapper.
EOF
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
    dest="${CRUCIBLE_CONFIG_DIR:-${repo_root}/aws/zipline-orchestration/.crucible-config/raw}"

    mkdir -p "${dest}"

    aws s3 cp "s3://${bucket}/terraform.tfvars" "${dest}/terraform.tfvars"
    aws s3 cp "s3://${bucket}/github.tf" "${dest}/github.tf"
    aws s3 cp "s3://${bucket}/cloudflare.tf" "${dest}/cloudflare.tf"
    aws s3 cp "s3://${bucket}/.terraform.lock.hcl" "${dest}/.terraform.lock.hcl"
    aws s3 cp "s3://${bucket}/crucible-config" "${dest}/crucible-config" --recursive

    cat <<EOF
Pulled AWS Crucible config into ${dest}.

This wrapper intentionally does not place the legacy *.tf files in the module
root, because those files belong to the old full AWS infrastructure root. Create
a local *.auto.tfvars.json for this Helm adoption root from the raw inputs and
live Helm values instead.
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
