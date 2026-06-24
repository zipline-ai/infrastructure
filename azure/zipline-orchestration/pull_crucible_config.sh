#!/usr/bin/env bash
set -euo pipefail

storage_account="${AZURE_CONFIG_STORAGE_ACCOUNT:-ziplineai2}"
container="${AZURE_CONFIG_CONTAINER:-dev-zipline-vars}"
prefix="${AZURE_CONFIG_PREFIX:-crucible-azure/zipline-orchestration}"

mkdir -p ".crucible-config/raw"

az storage blob download \
  --account-name "${storage_account}" \
  --container-name "${container}" \
  --name "${prefix}/backend.hcl" \
  --file "backend.hcl" \
  --auth-mode login \
  --overwrite true \
  --output none

az storage blob download \
  --account-name "${storage_account}" \
  --container-name "${container}" \
  --name "${prefix}/crucible.auto.tfvars.json" \
  --file "crucible.auto.tfvars.json" \
  --auth-mode login \
  --overwrite true \
  --output none

cat <<EOF
Pulled Azure Crucible orchestration config from:
  storage account: ${storage_account}
  container:       ${container}
  prefix:          ${prefix}

Local files are intentionally ignored by git:
  backend.hcl
  crucible.auto.tfvars.json
EOF
