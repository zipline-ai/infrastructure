{{/*
A compute namespace's contents (service accounts, RoleBindings, quota, LimitRange). Rendered per
namespace in values by compute-rbac.yaml, and once with a placeholder name into the ConfigMap the
Hub stamps out for runtime teams, so the two cannot drift.

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
-binding suffix: roleRef is immutable, so reusing the old Role-bound names would fail the upgrade.
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
The Hub's submit access, scoped to this namespace.
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
Required wherever a quota caps limits.*: Spark executors declare no limits, so without defaults
the quota rejects them.
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
