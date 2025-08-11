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
Generate domain for orchestration UI
*/}}
{{- define "zipline-orchestration.orchestrationUIDomain" -}}
{{- if .Values.domains.ziplineUI }}
{{- .Values.domains.ziplineUI }}
{{- else }}
{{- printf "%s.nip.io" .Values.staticIPs.orchestrationUI }}
{{- end }}
{{- end }}

{{/*
Generate domain for temporal UI
*/}}
{{- define "zipline-orchestration.temporalUIDomain" -}}
{{- if .Values.domains.temporal }}
{{- .Values.domains.temporal }}
{{- else }}
{{- printf "%s.nip.io" .Values.staticIPs.temporalUI }}
{{- end }}
{{- end }}

{{/*
Generate domain for orchestration hub
*/}}
{{- define "zipline-orchestration.orchestrationHubDomain" -}}
{{- if .Values.domains.hub }}
{{- .Values.domains.hub }}
{{- else }}
{{- printf "%s.nip.io" .Values.staticIPs.orchestrationHub }}
{{- end }}
{{- end }}