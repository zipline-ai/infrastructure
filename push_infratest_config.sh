#!/usr/bin/env bash
set -euo pipefail

# Uploads the git-ignored infratest orchestration config (backend + tfvars) from
# the selected cloud wrapper. The default remains AWS for compatibility with the
# nightly AWS e2e workflow.

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
src="${INFRATEST_CONFIG_ROOT:-${repo_root}/${cloud}/zipline-orchestration}"

for f in backend.hcl infratest.auto.tfvars; do
  [ -f "${src}/${f}" ] || { echo "Missing ${src}/${f}" >&2; exit 1; }
done

case "${cloud}" in
  aws)
    bucket="${INFRATEST_CONFIG_BUCKET:-infratest-opentofu-state}"
    for f in backend.hcl infratest.auto.tfvars; do
      aws s3 cp "${src}/${f}" "s3://${bucket}/${prefix}/${f}"
    done
    destination="s3://${bucket}/${prefix}"
    ;;
  azure)
    storage_account="${INFRATEST_CONFIG_STORAGE_ACCOUNT:?Set INFRATEST_CONFIG_STORAGE_ACCOUNT for Azure}"
    container="${INFRATEST_CONFIG_CONTAINER:-infratest-opentofu-state}"
    for f in backend.hcl infratest.auto.tfvars; do
      az storage blob upload --account-name "${storage_account}" --container-name "${container}" --name "${prefix}/${f}" --file "${src}/${f}" --auth-mode login --overwrite true --output none
    done
    destination="Azure ${storage_account}/${container}/${prefix}"
    ;;
  gcp)
    bucket="${INFRATEST_CONFIG_BUCKET:-infratest-opentofu-state}"
    for f in backend.hcl infratest.auto.tfvars; do
      gcloud storage cp "${src}/${f}" "gs://${bucket}/${prefix}/${f}"
    done
    destination="gs://${bucket}/${prefix}"
    ;;
esac

echo "Pushed infratest config to ${destination}."
