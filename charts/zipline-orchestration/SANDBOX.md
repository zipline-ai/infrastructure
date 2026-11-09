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

## Sandbox network isolation

When the conf repository URL is set, the chart also creates `sandbox-egress`
(Squid) and NetworkPolicies for the sandbox and proxy. This applies to compile
and agent sandboxes, regardless of whether the UI's agents flag is enabled.

The sandbox accepts connections only from UI pods in the release namespace.
Outbound connections are limited to kube-dns in `kube-system`, UI pods on the
configured UI container port, and the proxy on port 3128. The sandbox has no
direct outbound Internet rule. The proxy accepts connections only from sandbox
pods and permits HTTPS CONNECT to `github.com`, `pypi.org`, and
`files.pythonhosted.org`. Its outbound policy excludes private, loopback,
link-local (including cloud metadata), carrier-grade NAT, and multicast ranges.
Neither pod mounts a Kubernetes service-account token.

The UI's LLM proxy and MCP endpoints remain at
`http://orchestration-ui-service` (Service port 80). `SANDBOX_URL` remains
`http://sandbox-service:8000`. Kubernetes Services provide both routes, so no
Docker-style `sandbox-ingress` nginx container is needed. The sandbox bypasses
Squid for the internal UI address, including its namespace-qualified DNS names.
If overriding `orchestration.agents.llm_proxy_url`, ensure the destination is
permitted by these network rules.

Override `orchestration.sandbox.egress.allowedHosts` for other public Git hosts
or package mirrors. This replaces the list, so retain any defaults still needed.
A leading dot permits a domain and its subdomains, following Squid's dstdomain
syntax. Private Git hosts require an explicitly reviewed extension of the proxy
NetworkPolicy; adding them to the hostname list alone does not permit private
network access. Configure the proxy image and resource limits through
`orchestration.sandbox.egress.image` and `.resources`. Proxy scheduling inherits
the sandbox's node selector and tolerations.

### Required cluster setup

NetworkPolicies only isolate traffic when the cluster CNI enforces them. The
Terraform wrappers do not currently enable an enforcement engine; applying this
chart alone does not enable enforcement. Before enabling agents, configure and
verify enforcement on the target cluster:

- EKS: enable NetworkPolicy support in the Amazon VPC CNI add-on
  ([AWS instructions](https://docs.aws.amazon.com/eks/latest/userguide/cni-network-policy-configure.html)).
- AKS: enable a supported network policy engine for Azure CNI Overlay
  ([Azure instructions](https://learn.microsoft.com/en-us/azure/aks/use-network-policies)).
- GKE: enable NetworkPolicy enforcement or use Dataplane V2
  ([GKE instructions](https://cloud.google.com/kubernetes-engine/docs/how-to/network-policy)).

Changing an existing cluster's networking can roll or recreate nodes. This PR
does not change cluster networking. DNS rules assume CoreDNS/kube-dns pods with
`k8s-app=kube-dns` in `kube-system`. Clusters using NodeLocal DNS or custom DNS
need corresponding policy rules before rollout. Other cluster-wide policies
can add or further restrict connectivity; review the combined policies.

After deployment, verify allowed and blocked connections from the sandbox pod:
UI requests and GitHub/PyPI requests through the proxy should succeed; direct
Internet requests, metadata requests, and requests through the proxy to an
unlisted host should fail. Also verify requests from unrelated pods to the
sandbox API fail. Render tests check the manifests; they do not prove that the
cluster enforces the policies.
