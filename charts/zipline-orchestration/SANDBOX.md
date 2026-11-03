# Conf repository and sandbox

Set `orchestration.conf_repo.url` in the Terraform inputs to deploy the internal
sandbox and enable repository configuration in the UI. Omit it or leave it empty
to deploy neither the sandbox Deployment nor its Service. This interface works
with the AWS, Azure, and GCP wrappers.

```hcl
orchestration = {
  # Include the other required orchestration inputs for your deployment.
  conf_repo = {
    url              = "https://github.com/example/conf"
    path             = "python/conf"
    branch           = "main"
    zipline_env       = "canary"
    github_client_id = "your-github-oauth-client-id"
    github_scope     = "repo"
    github_token_remote_ref = {
      key = "<cloud-secret-reference>"
    }
    github_client_secret_remote_ref = {
      key = "<cloud-secret-reference>"
    }
  }
}
```

Use a Secrets Manager ARN for AWS, a Key Vault secret name for Azure, or a
Secret Manager ID for GCP. Add `property` when the remote secret contains a JSON
object rather than a single value. Create the secret values in the cloud secret
store before deployment; these inputs only reference them. AWS and GCP grant the
existing External Secrets identity access to these references. Azure uses the
existing Key Vault and its vault-level Secrets User role.

External Secrets Operator syncs the supplied references into
`conf-repo-credentials`, using keys `github-token` and `github-client-secret`.
The UI reads them through `secretKeyRef` as `CONF_REPO_GITHUB_TOKEN` and
`CONF_REPO_GITHUB_CLIENT_SECRET`. Both references are optional: public repositories
and configurations without GitHub OAuth do not need both. If External Secrets is
disabled, provision that Kubernetes Secret with the configured keys yourself.
Do not pass token or client secret values through Terraform or Helm.

The other UI variables map from `conf_repo`: `url` → `CONF_REPO_URL`, `path` →
`CONF_REPO_PATH`, `branch` → `CONF_REPO_BRANCH`, `zipline_env` → `ZIPLINE_ENV`,
`github_client_id` → `CONF_REPO_GITHUB_CLIENT_ID`, and `github_scope` →
`CONF_REPO_GITHUB_SCOPE`. Defaults are an empty path, branch `main`, environment
`default`, and scope `repo`.

The sandbox runs `ziplineai/sandbox:<global.version>`. Wait for the platform image
publishing change and select a version that includes this image before enabling
it. It exposes only a ClusterIP Service. The UI receives
`SANDBOX_URL=http://sandbox-service:8000`. Authentication follows `auth.enabled`;
the sandbox verifies JWTs against the UI's internal `/api/auth/jwks` endpoint.
GitHub credentials are never configured on the sandbox container.

The single sandbox replica uses an ephemeral `/sandboxes` cache. Restarting it
loses cached clones and CLI installations; later requests recreate them. The
container runs with filesystem group 1001 so its non-root user can write the
volume. The default CLI mode is `source`, matching the platform's local stack.
Configure `orchestration.sandbox` using chart value names to override `cli`,
`image`, `port`, `resources`, `nodeSelector`, or `tolerations`. No public ingress
or persistent disk is created.

For Helm-only installations use `orchestration.confRepo` in `values.yaml`,
including `credentialsSecret`, `tokenKey`, and `clientSecretKey` to reference an
existing Kubernetes Secret. The cloud secret synchronization is supplied by
Terraform.
