#!/usr/bin/env bash
set -euo pipefail

bucket="${CRUCIBLE_CONFIG_BUCKET:-zipline-crucible-vars}"
src="${CRUCIBLE_CONFIG_DIR:-.crucible-config/raw}"

aws s3 cp "${src}/terraform.tfvars" "s3://${bucket}/terraform.tfvars"
aws s3 cp "${src}/github.tf" "s3://${bucket}/github.tf"
aws s3 cp "${src}/cloudflare.tf" "s3://${bucket}/cloudflare.tf"
aws s3 cp "${src}/.terraform.lock.hcl" "s3://${bucket}/.terraform.lock.hcl"
aws s3 cp "${src}/crucible-config" "s3://${bucket}/crucible-config" --recursive
