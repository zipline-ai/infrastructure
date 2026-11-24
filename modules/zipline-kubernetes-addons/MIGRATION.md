# Operator namespace migration

The Zipline orchestration module now installs its operators in the orchestration
namespace, normally `zipline-system`. Existing installations may instead have
these Helm releases in dedicated namespaces:

| Release | Previous namespace |
| --- | --- |
| `external-secrets` | `external-secrets` |
| `cert-manager` | `cert-manager` |
| `opentelemetry-operator` | `opentelemetry-operator-system` |
| `flink-kubernetes-operator` | `flink-operator` |
| `kuberay-operator` | `kuberay-operator` |

Do not apply the Terraform namespace change directly to such a cluster. Helm
identifies a release by name and namespace, so Terraform would uninstall the
old release before creating the new one. External Secrets and cert-manager
manage their CRDs as regular Helm resources; uninstalling either release can
also delete its custom resources.

## Migration procedure

Perform the migration during a maintenance window. Use Helm 3.17 or newer so
`helm upgrade --install --take-ownership` is available. Run the commands against
the intended cluster context. The versions below match this module's defaults;
if an installed release uses another version, retain that version during the
move and upgrade it separately.

1. Confirm the target namespace and save the existing release values:

   ```bash
   kubectl get namespace zipline-system

   helm get values external-secrets --namespace external-secrets --output yaml > /tmp/external-secrets-values.yaml
   helm get values cert-manager --namespace cert-manager --output yaml > /tmp/cert-manager-values.yaml
   helm get values flink-kubernetes-operator --namespace flink-operator --output yaml > /tmp/flink-kubernetes-operator-values.yaml
   helm get values kuberay-operator --namespace kuberay-operator --output yaml > /tmp/kuberay-operator-values.yaml
   ```

   If OpenTelemetry is enabled, also save its values:

   ```bash
   helm get values opentelemetry-operator --namespace opentelemetry-operator-system --output yaml > /tmp/opentelemetry-operator-values.yaml
   ```

2. Pause the old controllers so the old and new releases do not reconcile the
   same resources concurrently:

   ```bash
   kubectl scale deployment --all --replicas=0 --namespace external-secrets
   kubectl scale deployment --all --replicas=0 --namespace cert-manager
   kubectl scale deployment --all --replicas=0 --namespace flink-operator
   kubectl scale deployment --all --replicas=0 --namespace kuberay-operator
   kubectl scale deployment --all --replicas=0 --namespace opentelemetry-operator-system
   ```

   Omit commands for operators that are not installed.

3. Install the same chart versions in `zipline-system` and transfer ownership
   of existing cluster-scoped resources:

   ```bash
   helm upgrade --install external-secrets external-secrets \
     --repo https://charts.external-secrets.io \
     --version 2.7.0 \
     --namespace zipline-system \
     --values /tmp/external-secrets-values.yaml \
     --take-ownership \
     --wait

   helm upgrade --install cert-manager cert-manager \
     --repo https://charts.jetstack.io \
     --version v1.13.3 \
     --namespace zipline-system \
     --values /tmp/cert-manager-values.yaml \
     --take-ownership \
     --wait

   helm upgrade --install flink-kubernetes-operator flink-kubernetes-operator \
     --repo https://archive.apache.org/dist/flink/flink-kubernetes-operator-1.14.0/ \
     --version 1.14.0 \
     --namespace zipline-system \
     --values /tmp/flink-kubernetes-operator-values.yaml \
     --take-ownership \
     --wait

   helm upgrade --install kuberay-operator kuberay-operator \
     --repo https://ray-project.github.io/kuberay-helm/ \
     --version 1.7.0 \
     --namespace zipline-system \
     --values /tmp/kuberay-operator-values.yaml \
     --take-ownership \
     --wait
   ```

   If OpenTelemetry is enabled:

   ```bash
   helm upgrade --install opentelemetry-operator opentelemetry-operator \
     --repo https://open-telemetry.github.io/opentelemetry-helm-charts \
     --version 0.47.0 \
     --namespace zipline-system \
     --values /tmp/opentelemetry-operator-values.yaml \
     --take-ownership \
     --wait
   ```

4. Verify the new controllers and existing custom resources before removing
   anything:

   ```bash
   kubectl get deployments --namespace zipline-system
   kubectl get externalsecrets.external-secrets.io --all-namespaces
   kubectl get flinkdeployments.flink.apache.org --all-namespaces
   kubectl get rayjobs.ray.io --all-namespaces
   ```

   If cert-manager or OpenTelemetry is in use, also verify their resources:

   ```bash
   kubectl get certificates.cert-manager.io --all-namespaces
   kubectl get opentelemetrycollectors.opentelemetry.io --all-namespaces
   ```

5. Reconcile OpenTofu state with the releases that now exist in
   `zipline-system`. Run these commands from the cloud root module directory:

   ```bash
   tofu state pull > /tmp/zipline-operator-namespace-migration.tfstate

   tofu state rm 'module.zipline_orchestration.module.addons.helm_release.external_secrets_operator[0]'
   tofu import 'module.zipline_orchestration.module.addons.helm_release.external_secrets_operator[0]' 'zipline-system/external-secrets'

   tofu state rm 'module.zipline_orchestration.module.addons.helm_release.cert_manager[0]'
   tofu import 'module.zipline_orchestration.module.addons.helm_release.cert_manager[0]' 'zipline-system/cert-manager'

   tofu state rm 'module.zipline_orchestration.module.addons.helm_release.flink_operator[0]'
   tofu import 'module.zipline_orchestration.module.addons.helm_release.flink_operator[0]' 'zipline-system/flink-kubernetes-operator'

   tofu state rm 'module.zipline_orchestration.module.addons.helm_release.kuberay_operator[0]'
   tofu import 'module.zipline_orchestration.module.addons.helm_release.kuberay_operator[0]' 'zipline-system/kuberay-operator'
   ```

   If OpenTelemetry is enabled:

   ```bash
   tofu state rm 'module.zipline_orchestration.module.addons.helm_release.opentelemetry_operator[0]'
   tofu import 'module.zipline_orchestration.module.addons.helm_release.opentelemetry_operator[0]' 'zipline-system/opentelemetry-operator'
   ```

   If the orchestration namespace is overridden, replace `zipline-system` in
   the Helm and import commands with that namespace.

6. Run `tofu plan`. It must show in-place reconciliation for the imported
   releases, not release replacement. Resolve any values drift before applying.

7. Delete the old dedicated namespaces only after the plan is clean, the new
   controllers are healthy, and each old namespace contains no unrelated
   resources:

   ```bash
   kubectl delete namespace external-secrets cert-manager flink-operator kuberay-operator opentelemetry-operator-system --ignore-not-found
   ```

Deleting the old namespaces removes their Helm release records and stopped
namespaced controller resources. The cluster-scoped resources are retained by
the releases in `zipline-system`.
