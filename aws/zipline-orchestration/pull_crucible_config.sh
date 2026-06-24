#!/usr/bin/env bash
set -euo pipefail

bucket="${CRUCIBLE_CONFIG_BUCKET:-zipline-crucible-vars}"
dest="${CRUCIBLE_CONFIG_DIR:-.crucible-config/raw}"

mkdir -p "${dest}"

aws s3 cp "s3://${bucket}/terraform.tfvars" "${dest}/terraform.tfvars"
aws s3 cp "s3://${bucket}/github.tf" "${dest}/github.tf"
aws s3 cp "s3://${bucket}/cloudflare.tf" "${dest}/cloudflare.tf"
aws s3 cp "s3://${bucket}/.terraform.lock.hcl" "${dest}/.terraform.lock.hcl"
aws s3 cp "s3://${bucket}/crucible-config" "${dest}/crucible-config" --recursive

cat <<EOF
Pulled raw Crucible config into ${dest}.

This wrapper intentionally does not place the legacy *.tf files in the module
root, because those files belong to the old full AWS infrastructure root. Create
a local *.auto.tfvars.json for this Helm adoption root from the raw inputs and
live Helm values instead.
EOF
