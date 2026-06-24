#!/usr/bin/env bash
set -euo pipefail

storage_account="${AZURE_CONFIG_STORAGE_ACCOUNT:-ziplineai2}"
container="${AZURE_CONFIG_CONTAINER:-dev-zipline-vars}"
prefix="${AZURE_CONFIG_PREFIX:-crucible-azure/zipline-orchestration}"

for file in backend.hcl crucible.auto.tfvars.json; do
  if [ ! -f "${file}" ]; then
    echo "Missing ${file}; run from azure/zipline-orchestration after generating local config." >&2
    exit 1
  fi
done

az storage blob upload \
  --account-name "${storage_account}" \
  --container-name "${container}" \
  --name "${prefix}/backend.hcl" \
  --file "backend.hcl" \
  --auth-mode login \
  --overwrite true \
  --output none

az storage blob upload \
  --account-name "${storage_account}" \
  --container-name "${container}" \
  --name "${prefix}/crucible.auto.tfvars.json" \
  --file "crucible.auto.tfvars.json" \
  --auth-mode login \
  --overwrite true \
  --output none
