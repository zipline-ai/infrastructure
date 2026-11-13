{{/*
Everything a compute namespace needs besides the Namespace object itself: the engine service
accounts with their workload-identity annotations, RoleBindings to the shared ClusterRoles, the
resource quotas, and the LimitRange those quotas depend on.

One definition, two consumers. compute-rbac.yaml renders it per namespace listed in values, and
compute-namespace-template.yaml renders it once with a placeholder name into a ConfigMap the Hub
mounts and stamps out for teams created at runtime. That is the point: the Hub does not need to
know what a compute namespace contains, and a namespace it creates cannot drift from one the chart
renders, because both come from here.

Call with a dict of:
  root      the chart context
  namespace the namespace name, or the placeholder token for the template
  overrides optional per-namespace dict from .Values.compute.namespaces (quota, limitRange, …)
*/}}
{{- define "zipline-orchestration.computeNamespaceResources" -}}
{{- $root := .root }}
{{- $ns := .namespace }}
{{- $overrides := .overrides | default dict }}
{{- $defaults := $root.Values.compute.namespaceDefaults | default dict }}
{{- $quota := $overrides.resourceQuota | default ($defaults.resourceQuota | default dict) }}
{{- $quotaEnabled := true }}
{{- if hasKey $quota "enabled" }}{{- $quotaEnabled = $quota.enabled }}{{- end }}
{{- $quotaHard := $quota.hard | default dict }}
{{- $limitRange := $overrides.limitRange | default ($defaults.limitRange | default dict) }}
{{- $limitRangeEnabled := true }}
{{- if hasKey $limitRange "enabled" }}{{- $limitRangeEnabled = $limitRange.enabled }}{{- end }}
{{- $limitRangeHasSpec := or (gt (len ($limitRange.default | default dict)) 0) (gt (len ($limitRange.defaultRequest | default dict)) 0) (gt (len ($limitRange.min | default dict)) 0) (gt (len ($limitRange.max | default dict)) 0) (gt (len ($limitRange.maxLimitRequestRatio | default dict)) 0) }}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ $root.Values.compute.serviceAccount.sparkName }}
  namespace: {{ $ns }}
  labels:
    {{- include "zipline-orchestration.labels" $root | nindent 4 }}
    app.kubernetes.io/component: spark-driver
  {{- with $root.Values.compute.serviceAccount.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ $root.Values.compute.serviceAccount.flinkName }}
  namespace: {{ $ns }}
  labels:
    {{- include "zipline-orchestration.labels" $root | nindent 4 }}
    app.kubernetes.io/component: flink-job
  {{- with ($root.Values.compute.flinkDefaults).serviceAccountAnnotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- /*
RoleBindings, not Roles. The rules live in ClusterRoles rendered once by
compute-cluster-roles.yaml, so adding a permission is one edit rather than one per namespace — and
a namespace the Hub stamps out cannot be missing a rule somebody added later.

Named with a -binding suffix on purpose: roleRef is immutable, so reusing the old `spark-driver`
and `flink-jobmanager` RoleBinding names while changing their roleRef from Role to ClusterRole
would fail the Helm upgrade rather than update in place.
*/}}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: spark-driver-binding
  namespace: {{ $ns }}
  labels:
    {{- include "zipline-orchestration.labels" $root | nindent 4 }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: {{ include "zipline-orchestration.fullname" $root }}-spark-driver
subjects:
  - kind: ServiceAccount
    name: {{ $root.Values.compute.serviceAccount.sparkName }}
    namespace: {{ $ns }}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: flink-jobmanager-binding
  namespace: {{ $ns }}
  labels:
    {{- include "zipline-orchestration.labels" $root | nindent 4 }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: {{ include "zipline-orchestration.fullname" $root }}-flink-jobmanager
subjects:
  - kind: ServiceAccount
    name: {{ $root.Values.compute.serviceAccount.flinkName }}
    namespace: {{ $ns }}
{{- /*
The Hub's own access to the namespace. This is what lets it submit a job there, and it is scoped to
this namespace rather than granted cluster-wide — so the Hub can reach the namespaces it has been
given and no others.
*/}}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: zipline-compute-submitter-binding
  namespace: {{ $ns }}
  labels:
    {{- include "zipline-orchestration.labels" $root | nindent 4 }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: {{ include "zipline-orchestration.fullname" $root }}-compute-submitter
subjects:
  - kind: ServiceAccount
    name: {{ include "zipline-orchestration.serviceAccountName" $root }}
    namespace: {{ $root.Release.Namespace }}
{{- if and $quotaEnabled (gt (len $quotaHard) 0) }}
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: zipline-compute
  namespace: {{ $ns }}
  labels:
    {{- include "zipline-orchestration.labels" $root | nindent 4 }}
    app.kubernetes.io/component: spark-compute
spec:
  hard:
    {{- toYaml $quotaHard | nindent 4 }}
{{- end }}
{{- if and $limitRangeEnabled $limitRangeHasSpec }}
{{- /*
Load-bearing wherever a quota caps limits.*: Kubernetes then requires every pod to declare that
limit, and Spark executors declare none. Without this the quota rejects them and the application
hangs rather than failing.
*/}}
---
apiVersion: v1
kind: LimitRange
metadata:
  name: zipline-compute-defaults
  namespace: {{ $ns }}
  labels:
    {{- include "zipline-orchestration.labels" $root | nindent 4 }}
    app.kubernetes.io/component: spark-compute
spec:
  limits:
    - type: Container
      {{- with $limitRange.default }}
      default:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with $limitRange.defaultRequest }}
      defaultRequest:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with $limitRange.min }}
      min:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with $limitRange.max }}
      max:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with $limitRange.maxLimitRequestRatio }}
      maxLimitRequestRatio:
        {{- toYaml . | nindent 8 }}
      {{- end }}
{{- end }}
{{- end -}}
