{{/*
Expand the name of the chart.
*/}}
{{- define "zipline-orchestration.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "zipline-orchestration.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "zipline-orchestration.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "zipline-orchestration.labels" -}}
helm.sh/chart: {{ include "zipline-orchestration.chart" . }}
{{ include "zipline-orchestration.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "zipline-orchestration.selectorLabels" -}}
app.kubernetes.io/name: {{ include "zipline-orchestration.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Service account name
*/}}
{{- define "zipline-orchestration.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "zipline-orchestration.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Controller Service name rendered by an aliased ingress-nginx subchart.
*/}}
{{- define "zipline-orchestration.ingressNginxFullname" -}}
{{- $root := .root -}}
{{- $alias := .alias -}}
{{- $values := index $root.Values $alias | default dict -}}
{{- if $values.fullnameOverride -}}
{{- $values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default $alias $values.nameOverride -}}
{{- if contains $name $root.Release.Name -}}
{{- $root.Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" $root.Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end }}

{{- define "zipline-orchestration.ingressNginxControllerServiceName" -}}
{{- $root := .root -}}
{{- $alias := .alias -}}
{{- $values := index $root.Values $alias | default dict -}}
{{- $controller := $values.controller | default dict -}}
{{- $controllerName := $controller.name | default "controller" -}}
{{- $fullname := include "zipline-orchestration.ingressNginxFullname" (dict "root" $root "alias" $alias) -}}
{{- printf "%s-%s" $fullname $controllerName | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/*
Public origin used by the UI for auth and server-side requests.
*/}}
{{- define "zipline-orchestration.uiOrigin" -}}
{{- if .Values.orchestration.ui.origin -}}
{{- .Values.orchestration.ui.origin -}}
{{- else if .Values.auth.url -}}
{{- .Values.auth.url -}}
{{- else if .Values.ingress.ui.host -}}
{{- printf "https://%s" .Values.ingress.ui.host -}}
{{- else -}}
{{- "" -}}
{{- end -}}
{{- end }}

{{/*
Default Kubernetes namespace used for Spark compute jobs.
*/}}
{{- define "zipline-orchestration.computeDefaultNamespace" -}}
{{- $defaultNamespace := .Values.compute.defaultNamespace | default "" -}}
{{- if $defaultNamespace -}}
{{- $defaultNamespace -}}
{{- else -}}
{{- $namespaces := .Values.compute.namespaces | default list -}}
{{- if gt (len $namespaces) 0 -}}
{{- (index $namespaces 0).name | default "zipline-default" -}}
{{- else -}}
{{- "zipline-default" -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Backward-compatible helper for the Hub's current single default namespace.
*/}}
{{- define "zipline-orchestration.computeJobNamespace" -}}
{{- include "zipline-orchestration.computeDefaultNamespace" . -}}
{{- end }}

{{/*
Namespace used for compute control-plane support services.
*/}}
{{- define "zipline-orchestration.computeSystemNamespace" -}}
{{- .Release.Namespace -}}
{{- end }}

{{/*
Bucket/container name. Callers pass the provider-native name only, not a URI.
*/}}
{{- define "zipline-orchestration.computeBucketName" -}}
{{- .Values.compute.objectStore.bucket -}}
{{- end }}

{{/*
Spark event log directory used by Spark History Server.
*/}}
{{- define "zipline-orchestration.sparkEventLogDir" -}}
{{- .Values.compute.sparkDefaults.eventLogDir -}}
{{- end }}

{{/*
JDBC URL for orchestration services.
*/}}
{{- define "zipline-orchestration.databaseJdbcUrl" -}}
{{- if .Values.database.jdbcUrl -}}
{{- .Values.database.jdbcUrl -}}
{{- else -}}
{{- $url := printf "jdbc:postgresql://%s:%v/%s" .Values.database.host (.Values.database.port | default 5432) .Values.database.name -}}
{{- if .Values.database.sslMode -}}
{{- printf "%s?sslmode=%s" $url .Values.database.sslMode -}}
{{- else -}}
{{- $url -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Postgres URL for services that expect a non-JDBC DATABASE_URL.
*/}}
{{- define "zipline-orchestration.databaseUrl" -}}
{{- if .Values.database.url -}}
{{- .Values.database.url -}}
{{- else -}}
{{- $url := printf "postgres://$(DB_USERNAME)@%s:%v/%s" .Values.database.host (.Values.database.port | default 5432) .Values.database.name -}}
{{- if .Values.database.sslMode -}}
{{- printf "%s?sslmode=%s" $url .Values.database.sslMode -}}
{{- else -}}
{{- $url -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Database credentials Secret references.
*/}}
{{- define "zipline-orchestration.databaseCredentialsSecretName" -}}
{{- .Values.database.credentialsSecret.name | default "db-credentials" -}}
{{- end }}

{{- define "zipline-orchestration.databaseCredentialsUsernameKey" -}}
{{- .Values.database.credentialsSecret.usernameKey | default "username" -}}
{{- end }}

{{- define "zipline-orchestration.databaseCredentialsPasswordKey" -}}
{{- .Values.database.credentialsSecret.passwordKey | default "password" -}}
{{- end }}

{{/*
Name of the SecretProviderClass mounted into orchestration pods.
*/}}
{{- define "zipline-orchestration.secretProviderClassName" -}}
{{- .Values.secrets.className | default "zipline-secret-provider" -}}
{{- end }}

{{/*
Spark History Server proxy base path.
*/}}
{{- define "zipline-orchestration.historyServerProxyBase" -}}
{{- printf "/%s" (trimAll "/" (.Values.compute.historyServer.proxyBase | default "spark-history")) -}}
{{- end }}

{{/*
Externally reachable Spark History Server URL, used by the Hub to render
links the operator clicks from a browser. When ingress.ui.host is set the
SHS is exposed behind <ui-host>/<proxyBase>; otherwise the Hub falls back
to the cluster-internal Service DNS which only works from inside the cluster.
*/}}
{{- define "zipline-orchestration.historyServerPublicUrl" -}}
{{- if .Values.ingress.ui.host -}}
{{- printf "https://%s%s" .Values.ingress.ui.host (include "zipline-orchestration.historyServerProxyBase" .) -}}
{{- else -}}
{{- printf "http://spark-history-server.%s.svc.cluster.local:18080" .Release.Namespace -}}
{{- end -}}
{{- end }}
