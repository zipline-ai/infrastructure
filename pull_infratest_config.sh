#!/usr/bin/env bash
set -euo pipefail

# Downloads the git-ignored infratest orchestration config (backend + tfvars,
# which carry secrets) into the selected cloud wrapper. The default remains AWS
# for compatibility with the nightly AWS e2e workflow.

if [ "$#" -gt 1 ]; then
  echo "Usage: $0 [aws|azure|gcp]" >&2
  exit 1
fi

cloud="${1:-aws}"
case "${cloud}" in
  aws|azure|gcp) ;;
  *)
    echo "Usage: $0 [aws|azure|gcp]" >&2
    exit 1
    ;;
esac
prefix="${INFRATEST_CONFIG_PREFIX:-config}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dest="${INFRATEST_CONFIG_ROOT:-${repo_root}/${cloud}/zipline-orchestration}"

mkdir -p "${dest}"
case "${cloud}" in
  aws)
    bucket="${INFRATEST_CONFIG_BUCKET:-infratest-opentofu-state}"
    for f in backend.hcl infratest.auto.tfvars; do
      aws s3 cp "s3://${bucket}/${prefix}/${f}" "${dest}/${f}"
    done
    source="s3://${bucket}/${prefix}"
    ;;
  azure)
    storage_account="${INFRATEST_CONFIG_STORAGE_ACCOUNT:?Set INFRATEST_CONFIG_STORAGE_ACCOUNT for Azure}"
    container="${INFRATEST_CONFIG_CONTAINER:-infratest-opentofu-state}"
    for f in backend.hcl infratest.auto.tfvars; do
      az storage blob download --account-name "${storage_account}" --container-name "${container}" --name "${prefix}/${f}" --file "${dest}/${f}" --auth-mode login --overwrite true --output none
    done
    source="Azure ${storage_account}/${container}/${prefix}"
    ;;
  gcp)
    bucket="${INFRATEST_CONFIG_BUCKET:-infratest-opentofu-state}"
    for f in backend.hcl infratest.auto.tfvars; do
      gcloud storage cp "gs://${bucket}/${prefix}/${f}" "${dest}/${f}"
    done
    source="gs://${bucket}/${prefix}"
    ;;
esac

echo "Pulled infratest config from ${source} into ${dest} (git-ignored)."
