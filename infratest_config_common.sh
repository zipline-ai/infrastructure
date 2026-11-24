# Shared settings for {pull,push,diff}_infratest_config.sh. Sourced, not run.
# Expects $cloud to be set by the caller.

case "${cloud}" in
  aws)
    config_uri="s3://${INFRATEST_CONFIG_BUCKET:-infratest-opentofu-state}/${INFRATEST_CONFIG_PREFIX:-config}"
    config_files=(backend.hcl infratest.auto.tfvars .terraform.lock.hcl)
    ;;
  gcp)
    config_uri="gs://${INFRATEST_CONFIG_BUCKET:-zipline-infratest-opentofu-state}/${INFRATEST_CONFIG_PREFIX:-config/gcp}"
    config_files=(backend.hcl infratest.auto.tfvars.json .terraform.lock.hcl)
    ;;
  *)
    echo "Usage: $0 [aws|gcp]" >&2
    exit 1
    ;;
esac

profile="${INFRATEST_PROFILE:-}"

copy_config() {
  if [ "${cloud}" = "gcp" ]; then
    gcloud storage cp --no-user-output-enabled "$1" "$2"
  elif [ -n "${profile:-}" ]; then
    aws --profile "${profile}" s3 cp "$1" "$2"
  else
    aws s3 cp "$1" "$2"
  fi
}
