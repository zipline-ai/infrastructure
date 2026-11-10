# Agent provider credentials

The AWS, Azure, and GCP Terraform wrappers accept optional deployment-level
provider key references under `orchestration.agents`. Secret values stay in the
cloud secret store; do not pass them through Terraform or Helm.

```hcl
orchestration = {
  # Include the other required orchestration inputs.
  agents = {
    enable = true
    anthropic_api_key_remote_ref = {
      key = "<cloud-secret-reference>"
    }
    openai_api_key_remote_ref = {
      key = "<cloud-secret-reference>"
    }
  }
}
```

Use these reference formats:

| Cloud | `key` | `property` |
| --- | --- | --- |
| AWS Secrets Manager | Full secret ARN | JSON field name, if the secret stores an object |
| Azure Key Vault | Secret name in the configured vault | Omit for a secret containing the API key directly |
| GCP Secret Manager | Secret ID or `projects/<project>/secrets/<name>` | JSON field name, if the secret stores an object |

For example, two keys stored in one JSON secret can share the same `key` and
use `property = "anthropic"` and `property = "openai"` respectively. Either
provider reference can be omitted; agents can still use user-configured keys.
When agents are disabled, these references are ignored.

External Secrets Operator creates `agents-provider-credentials` in the release
namespace. Its configured keys are `AGENTS_ANTHROPIC_API_KEY` and
`AGENTS_OPENAI_API_KEY`. The UI reads each through `secretKeyRef`; credentials
are not configured on the sandbox. AWS and GCP grant the existing External
Secrets identity access to these references. Azure uses the existing Key Vault
Secrets User role and vault. Customer-managed KMS keys or cross-account/project
secrets can require additional grants on the remote secret or encryption key.

Create the cloud secret values before applying. With
`orchestration.secrets.external_secrets_enabled = false`, provision the Kubernetes
Secret yourself using the same name and keys. Secret rotation updates the
Kubernetes Secret; restart the UI pods to load changed environment values.
