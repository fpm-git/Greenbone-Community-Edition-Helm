{{/*
Expand the name of the chart.
*/}}
{{- define "openvas.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "openvas.fullname" -}}
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
Allow the release namespace to be overridden for multi-namespace deployments in combined charts
*/}}
{{- define "openvas.namespace" -}}
  {{- if .Values.namespaceOverride -}}
    {{- .Values.namespaceOverride -}}
  {{- else -}}
    {{- .Release.Namespace -}}
  {{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "openvas.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "openvas.labels" -}}
helm.sh/chart: {{ include "openvas.chart" . }}
{{ include "openvas.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "openvas.selectorLabels" -}}
app.kubernetes.io/name: {{ include "openvas.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}-{{ include "openvas.name" . }}
workload.user.cattle.io/workloadselector: "deployment-{{template "openvas.namespace" .}}-{{include "openvas.fullname" .}}"
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "openvas.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "openvas.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Container securityContext shared by all containers
*/}}
{{- define "openvas.containerSecurityContext" -}}
{{- toYaml .Values.containerSecurityContext }}
{{- end }}

{{/*
securityContext for ospd-openvas: shared settings plus the capabilities and
seccomp profile it needs for raw-socket scanning
*/}}
{{- define "openvas.ospdSecurityContext" -}}
{{- $ctx := omit (deepCopy .Values.containerSecurityContext) "capabilities" "seccompProfile" }}
{{- with .Values.ospdOpenvas.capabilities }}
{{- $_ := set $ctx "capabilities" . }}
{{- end }}
{{- with .Values.ospdOpenvas.seccompProfile }}
{{- $_ := set $ctx "seccompProfile" . }}
{{- end }}
{{- toYaml $ctx }}
{{- end }}

{{/*
Resources for a container, looked up by name in .Values.resources
Usage: include "openvas.resources" (dict "root" . "name" "gvmd")
*/}}
{{- define "openvas.resources" -}}
{{- with (get (default dict .root.Values.resources) .name) }}
resources:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{/*
securityContext for the "openvas" log container: it only reads openvas.conf
and tails the (0666) scanner log, so it can run non-root and read-only
*/}}
{{- define "openvas.logSecurityContext" -}}
{{- $ctx := deepCopy .Values.containerSecurityContext }}
{{- $_ := set $ctx "runAsUser" 65534 }}
{{- $_ := set $ctx "runAsGroup" 65534 }}
{{- $_ := set $ctx "runAsNonRoot" true }}
{{- $_ := set $ctx "readOnlyRootFilesystem" true }}
{{- $_ := set $ctx "capabilities" (dict "drop" (list "ALL")) }}
{{- toYaml $ctx }}
{{- end }}
