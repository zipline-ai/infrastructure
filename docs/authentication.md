# Application authentication setup

This guide covers Zipline user login through Google, GitHub, Microsoft Entra,
generic OpenID Connect (OIDC), and SAML. It covers the AWS and Azure orchestration
wrappers and their shared Helm chart. Cloud operator credentials, Kubernetes
administrator access, workload identity setup, and Polaris credentials are outside
this guide. Enabling login does not replace those identities.

## Deployment contract and prerequisites

1. Choose the final public HTTPS origin, for example `https://zipline.example.com`.
   Configure DNS, ingress, and TLS before testing login. The browser must reach
   the UI and the UI must reach the identity provider (IdP).
2. Choose the provider and obtain permission to create its application registration,
   assign users, and manage its credentials. Use separate registrations and secrets
   for separate environments.
3. Determine the callback URL from the **deployed UI version**. This repository
   deploys the UI image but does not contain its authentication implementation.
   It cannot establish OAuth callback paths, SAML entity ID conventions, required
   claims, account provisioning rules, or accepted Zipline role names.
   Obtain these from the UI configuration/source or its maintainer before
   completing the IdP registration. For OAuth/OIDC, the `redirect_uri` in a login
   authorization request is also evidence of the callback the UI uses. Do not
   substitute the homepage, `/auth/login`, `/auth/forward`, or the JWKS endpoint.
4. Merge the following into the environment's existing orchestration configuration;
   preserve its other settings:

   ```hcl
   orchestration = {
     # Preserve existing ingress, database, compute, and other configuration.
     ui = {
       origin = "https://zipline.example.com"
     }
     auth = {
       enabled = true
       url     = "https://zipline.example.com"
       # Add the selected provider's fields below.
     }
   }
   ```

   Set `auth.url` explicitly: the UI template passes it directly as `AUTH_URL`.
   Keep it consistent with the public UI origin and the deployed application's
   base-URL contract. Provider IDs alone do not enable authentication; the shared
   switch is `auth.enabled`, which defaults to false.
5. Provision the secrets described next, add provider settings, then plan and apply
   the deployment. Do not expose an environment to users until login and access
   checks pass.

## Secret delivery: required for every provider

The UI reads a Kubernetes Secret named `auth-secret` in the release namespace.
The wrappers use External Secrets Operator (ESO) to create it from the cloud
secret store. The following key names are exact:

| Kubernetes key | Value |
| --- | --- |
| `auth-secret` | Stable, high-entropy application authentication secret |
| `google-oauth-client-secret` | Google client secret, or unused placeholder |
| `github-oauth-client-secret` | GitHub client secret, or unused placeholder |
| `microsoft-entra-oauth-client-secret` | Entra client secret, or unused placeholder |
| `sso-client-secret` | Generic OIDC client secret, or unused placeholder |
| `sso-saml-cert` | IdP signing certificate; required when `sso_use_saml = true` |

**All five base keys are requested even when only one provider is used.** The
chart references Google, GitHub, and Entra secret keys unconditionally when auth
is enabled; the OIDC branch also references `sso-client-secret`. Missing remote
keys can prevent ESO synchronization and missing Kubernetes keys can prevent UI
startup. AWS-created secrets use empty strings for unused provider secrets. For
external stores, provision every required key; if the store rejects empty values,
use a nonempty unused placeholder and leave that provider's client ID unset.
Verify the UI does not offer unused providers.

Generate `auth-secret` using a cryptographically secure generator (for example
`openssl rand -hex 32`), subject to the UI version's secret requirements. Keep it
stable across replicas and deploys. Store credentials outside version control.
Supplying secrets through Terraform/OpenTofu can record them in state; protect
state and plan artifacts as credentials.

### AWS: existing Secrets Manager secret

1. Create a Secrets Manager secret in the deployment's AWS region containing a
   JSON object with the hyphenated keys above. Include `sso-saml-cert` for SAML.
2. Set `aws.auth_secret_arn` to its ARN in the existing `aws` configuration.
   Alternatively set `orchestration.auth.secrets_arn`. Use one reference to avoid
   ambiguity; the AWS-specific field is preferred by the wrapper's lookup.
3. Leave `aws.auth_secret_values` empty. A nonempty values map makes the wrapper
   create and use a new secret instead.
4. Confirm the workload can read the secret and, for a customer-managed encryption
   key, has the required decrypt permission. The wrapper includes the selected
   secret ARN in its workload permissions; custom KMS policies still need review.

The wrapper maps each JSON property to the matching Kubernetes key. See
[AWS authentication configuration](../aws/zipline-orchestration/README.md#authentication).

### AWS: wrapper-created Secrets Manager secret

Instead of supplying an ARN, merge this into the existing AWS configuration:

```hcl
aws = {
  # Preserve other AWS settings. Inject real values from protected configuration.
  auth_secret_values = {
    google_oauth_client_secret = "REPLACE_WITH_GOOGLE_SECRET"
  }
}
```

The nonempty map requests secret creation. Its supported keys are `auth_secret`,
`google_oauth_client_secret`, `github_oauth_client_secret`,
`microsoft_entra_oauth_client_secret`, `sso_client_secret`, and `sso_saml_cert`.
Only supply the provider values you use. The wrapper generates `auth-secret` if
`auth_secret` is omitted and supplies empty strings for omitted provider values.
For SAML, supply `sso_saml_cert`. These underscore names are input fields; the
created secret uses the hyphenated names in the table.

### Azure: Key Vault

1. Identify the vault configured by `azure.keyvault_name` (default
   `<customer_name>-zipline-secrets`). Coordinate initial provisioning if the
   wrapper has not created it yet; auth secret values must exist before ESO can
   successfully synchronize the application secret.
2. Create a separate Key Vault secret for **each** required hyphenated key above.
   These are individual secrets, not properties of one JSON secret. Supply the
   active provider's credential and placeholders for unused providers.
3. Add `sso-saml-cert` with the IdP certificate when using SAML. Preserve its
   certificate formatting as required by the UI.
4. Confirm the configured workload identity and SecretStore can read the vault.
   The Azure wrapper does not populate these application auth credentials for you.
5. Apply the configuration and check ESO readiness before testing login.

See [Azure secrets](../azure/zipline-orchestration/README.md#secrets).

## Google OAuth

1. In the Google Cloud project for this environment, configure the OAuth consent
   screen/audience and permitted test users or production availability.
2. Create an OAuth client for a **web application**. Register the exact UI callback
   URL established above as an authorized redirect URI. Configure authorized
   JavaScript origins only if the UI integration requires them.
3. Record the client ID and store the client secret as
   `google-oauth-client-secret` (AWS values field: `google_oauth_client_secret`).
4. Add `google_oauth_client_id = "YOUR_CLIENT_ID"` inside `orchestration.auth`.
5. Deploy and test an assigned/allowed Google account. Test an account outside
   the intended audience as well. Consent-screen audience settings and the
   application's own authorization rules must match the intended access policy.

Follow [Google's web-server OAuth instructions](https://developers.google.com/identity/protocols/oauth2/web-server)
for registration and redirect URI matching.

## GitHub OAuth

1. Create a GitHub **OAuth App** under the intended user or organization owner.
   Set its homepage to the public UI URL and its authorization callback URL to
   the exact callback used by the deployed UI.
2. Record its client ID and generate a client secret. Store the secret as
   `github-oauth-client-secret` (AWS values field: `github_oauth_client_secret`).
3. Add `github_oauth_client_id = "YOUR_CLIENT_ID"` inside `orchestration.auth`.
4. Resolve any organization OAuth-app approval policy with the organization owner.
   Do not assume that authenticating with GitHub restricts access to organization
   members; establish and test Zipline's authorization policy separately.
5. Deploy and test approved and unapproved users. Use separate OAuth Apps when
   environments need different callbacks; GitHub OAuth Apps have one callback URL.

See [GitHub OAuth App registration](https://github.com/github/docs/blob/main/content/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app.md).

## Microsoft Entra

1. Register an application in the intended Entra tenant. Choose supported account
   types according to your access policy; record the directory (tenant) ID and
   application (client) ID.
2. Add a **Web** redirect URI matching the deployed UI's callback. Create a client
   secret, record its **value**, and track its expiration date.
3. Store the value as `microsoft-entra-oauth-client-secret` (AWS values field:
   `microsoft_entra_oauth_client_secret`).
4. Add these fields inside `orchestration.auth`:

   ```hcl
   microsoft_entra_tenant_id       = "YOUR_TENANT_ID"
   microsoft_entra_oauth_client_id = "YOUR_CLIENT_ID"
   ```

5. Configure consent and user/group assignments according to the organization's
   policy and the UI's requested scopes. Do not add unrelated Graph permissions.
6. Deploy; test a permitted user and a user outside the intended tenant/assignment.
   Schedule credential rotation before the client secret expires.

See [Microsoft application registration](https://learn.microsoft.com/en-us/graph/auth-register-app-v2)
and [Web redirect URI configuration](https://learn.microsoft.com/entra/identity-platform/how-to-add-redirect-uri).

## Generic OIDC SSO

Use this option for an OIDC IdP not configured through the dedicated fields, or
when the UI requires a generic SSO connection.

1. Create a confidential web client in the IdP. Obtain the issuer, client ID, and
   client secret. Register the UI version's exact generic SSO callback URL.
2. Confirm issuer discovery, signing keys, and token endpoints are reachable from
   the UI. Confirm the UI's required scopes and identity claims with its maintainer.
3. Choose the provider identifier and domain according to the UI's SSO registration
   contract. A configured domain is metadata, not evidence of an access restriction.
4. Add these fields inside `orchestration.auth`:

   ```hcl
   sso_use_saml  = false
   sso_provider_id = "YOUR_PROVIDER_ID"
   sso_domain      = "example.com"
   sso_issuer      = "https://YOUR_IDP_ISSUER"
   sso_client_id   = "YOUR_CLIENT_ID"
   ```

5. Store the client secret as `sso-client-secret` (AWS values field:
   `sso_client_secret`). Leave unrelated provider client IDs unset.
6. Complete any SSO connection registration/provisioning required by the UI; this
   repository passes environment variables but does not demonstrate that workflow.
7. Deploy and test login, identity claims, and access restrictions. If you need
   group-based roles, complete the mapping steps below.

## SAML SSO

1. Create a SAML application in the IdP. Obtain the IdP SSO entry-point URL,
   issuer/entity ID, and signing certificate.
2. Obtain Zipline's service-provider entity ID, ACS/callback URL, NameID format,
   required attributes, and signing requirements from the deployed UI contract.
   Register those exact values with the IdP. The Terraform field names alone do
   not prove which party's entity ID the UI expects as `sso_saml_issuer`.
3. Add these fields inside `orchestration.auth`:

   ```hcl
   sso_use_saml          = true
   sso_provider_id       = "YOUR_PROVIDER_ID"
   sso_domain           = "example.com"
   sso_saml_entry_point  = "https://YOUR_IDP_SSO_ENDPOINT"
   sso_saml_issuer       = "ISSUER_EXPECTED_BY_THE_UI"
   sso_saml_callback_url = "https://zipline.example.com/EXACT_ACS_PATH"
   ```

4. Store the IdP signing certificate as `sso-saml-cert` (AWS values field:
   `sso_saml_cert`). Supply the certificate format the UI expects, preserving
   newlines where needed. This is the IdP certificate, not the ingress TLS
   certificate or an IdP private key.
5. Assign intended users/groups to the IdP application. Configure the agreed
   identity and group attributes. Complete any UI-side connection registration.
6. Deploy and test the supported login flow. Check audience, destination, issuer,
   certificate trust, and timestamps if assertions are rejected. Keep cluster and
   IdP clocks synchronized. Plan certificate rollover before expiration.

Setting `sso_use_saml` selects the SAML branch instead of the generic OIDC branch;
it does not remove the other mandatory base secret keys.

## Group claims and role mapping

The shared chart passes `idp_role_mapping` and `idp_group_claim` as string-valued
UI environment variables. It does not validate their syntax or define valid roles.

1. Confirm the mapping serialization, accepted role names, group-claim format,
   default role, and behavior for unmatched users in the deployed UI version.
2. Configure the IdP to emit the required group/role claim for assigned users.
   Check whether it emits stable IDs, names, or another representation.
3. Set `orchestration.auth.idp_group_claim` to the actual claim name and
   `orchestration.auth.idp_role_mapping` to the UI-supported serialized mapping.
   Do not assume a Terraform map or guessed JSON structure will be accepted.
4. Test each mapped role, multiple group memberships, and a user with no matching
   group. Verify actual permitted operations, not only successful login.

## Deploy and verify

Use the wrapper's normal backend initialization and environment configuration;
see the [AWS](../aws/zipline-orchestration/README.md) or
[Azure](../azure/zipline-orchestration/README.md) deployment instructions.

1. Run `tofu plan` in the selected wrapper with the environment's normal variable
   inputs. Review secret references, public URL, provider settings, and unexpected
   infrastructure changes before running `tofu apply` with those same inputs.
2. Check secret synchronization and UI rollout (replace the default namespace if
   your release uses a different one):

   ```sh
   kubectl -n zipline-system get externalsecret auth-secret
   kubectl -n zipline-system describe externalsecret auth-secret
   kubectl -n zipline-system get deploy
   kubectl -n zipline-system get pods
   ```

   Require the ExternalSecret Ready condition and healthy UI pods. Inspect secret
   **key names**, not secret values, when diagnosing missing keys.
3. Open a private browser session at the public origin. Confirm the selected
   provider appears, login returns to the correct host, and refresh preserves the
   session. Verify logout and subsequent access to a protected route.
4. Verify an unauthenticated browser cannot perform protected operations. Verify
   intended users can log in and excluded/unmapped users receive the intended
   denial or restricted access. A successful callback alone is insufficient.
5. Exercise a protected Hub operation through ingress. With auth enabled, the
   chart configures nginx forward authentication through the UI's `/auth/forward`
   endpoint. Hub and Eval use the UI's internal `/api/auth/jwks` endpoint. Check
   these paths remain reachable and proxy behavior preserves cookies and headers.

## Troubleshooting and rotation

| Symptom | Checks |
| --- | --- |
| ExternalSecret not Ready | SecretStore identity/permissions, cloud region/vault, every mandatory remote key, AWS JSON property names versus Azure individual secret names |
| UI cannot start | Missing `auth-secret` or required keys; inspect pod events for `CreateContainerConfigError` |
| Provider absent | `auth.enabled`, selected client ID, actual deployed UI image and provider support |
| Callback rejected | Exact scheme, hostname, path, trailing slash, provider registration, `AUTH_URL`, and public origin |
| Invalid client | Matching client ID and secret value, tenant, expiration, and synchronized Kubernetes secret |
| Login loop | HTTPS/cookie behavior, proxy headers, consistent application secret across replicas, URL mismatch |
| SAML rejected | Correct signing certificate, issuer/audience/ACS, required attributes, clock skew |
| Login succeeds but role is wrong | Actual claim contents, mapping syntax, accepted roles, unmatched-user behavior |
| UI login works but Hub fails | Forward-auth configuration, cookie/header forwarding, internal UI service and JWKS reachability |

To rotate a provider secret, create its replacement at the IdP, update the cloud
secret, wait for ESO synchronization, then restart affected UI pods through the
normal deployment process. Kubernetes environment variables do not change in
running containers when a Secret changes. Verify login before revoking the old
credential. Treat application-secret rotation separately: confirm its effect on
sessions with the UI maintainer and coordinate replica restarts. For SAML signing
certificate rotation, coordinate the IdP change and application trust update.

## Implementation references

- [UI environment and secret wiring](../charts/zipline-orchestration/templates/orchestration-ui.yaml)
- [Shared module secret synchronization and auth passthrough](../modules/zipline-orchestration/main.tf)
- [AWS secret creation](../aws/zipline-orchestration/secrets.tf)
- [AWS secret references](../aws/zipline-orchestration/locals.tf)
- [Azure secret references](../azure/zipline-orchestration/locals.tf)
- [Chart defaults](../charts/zipline-orchestration/values.yaml)

The UI-specific contracts identified above must be resolved before production
setup; this infrastructure repository cannot supply those missing application details.
