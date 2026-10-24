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

{{/*
image and imagePullPolicy for a container
Usage: include "openvas.image" (dict "root" . "image" .Values.images.gvmd)
*/}}
{{- define "openvas.image" -}}
image: {{ printf "%s:%s" .image.repository (toString .image.tag) | quote }}
imagePullPolicy: {{ .image.pullPolicy | default .root.Values.imagePullPolicy }}
{{- end }}

{{/*
image and imagePullPolicy for a feed data image
Usage: include "openvas.feedImage" (dict "root" . "name" "scap-data")
*/}}
{{- define "openvas.feedImage" -}}
{{- $f := .root.Values.feedImages }}
image: {{ printf "%s/%s:%s" $f.registry .name (toString $f.tag) | quote }}
imagePullPolicy: {{ $f.pullPolicy | default .root.Values.imagePullPolicy }}
{{- end }}

{{/*
Probes for a container, looked up by name in .Values.probes
Usage: include "openvas.probes" (dict "root" . "name" "gvmd")
*/}}
{{- define "openvas.probes" -}}
{{- with (get (default dict .root.Values.probes) .name) }}
{{- toYaml . }}
{{- end }}
{{- end }}

{{/*
securityContext for redis-server: shared settings merged with redis.securityContext
*/}}
{{- define "openvas.redisSecurityContext" -}}
{{- $ctx := mergeOverwrite (deepCopy .Values.containerSecurityContext) (deepCopy .Values.redis.securityContext) }}
{{- toYaml $ctx }}
{{- end }}

{{/*
redis-server container. Runs as a native sidecar (restartPolicy: Always in
initContainers) when nativeSidecars is true so it stops after ospd-openvas.
Usage: include "openvas.redisContainer" (dict "root" . "sidecar" true)
*/}}
{{- define "openvas.redisContainer" -}}
{{- $root := .root }}
- name: redis-server
  {{- include "openvas.image" (dict "root" $root "image" $root.Values.redis.image) | nindent 2 }}
  {{- if .sidecar }}
  restartPolicy: Always
  {{- end }}
  command: ["redis-server", "/etc/redis/redis.conf"]
  volumeMounts:
    - name: redis-config
      mountPath: /etc/redis
      readOnly: true
    - name: redis-socket
      mountPath: /run/redis
    - name: redis-data
      mountPath: /data
  securityContext:
    {{- include "openvas.redisSecurityContext" $root | nindent 4 }}
  {{- include "openvas.probes" (dict "root" $root "name" "redis-server") | nindent 2 }}
  {{- include "openvas.resources" (dict "root" $root "name" "redis-server") | nindent 2 }}
{{- end }}

{{/*
pg-gvm container. Runs as a native sidecar when nativeSidecars is true so
PostgreSQL stops after gvmd instead of underneath it.
Usage: include "openvas.pgContainer" (dict "root" . "sidecar" true)
*/}}
{{- define "openvas.pgContainer" -}}
{{- $root := .root }}
- name: pg-gvm
  {{- include "openvas.image" (dict "root" $root "image" $root.Values.psgvm.image) | nindent 2 }}
  {{- if .sidecar }}
  restartPolicy: Always
  {{- end }}
  volumeMounts:
    - name: psql-storage
      mountPath: /var/lib/postgresql
    - name: shared-storage
      mountPath: /var/run/postgresql
      subPath: psql-socket
  securityContext:
    {{- include "openvas.containerSecurityContext" $root | nindent 4 }}
  {{- include "openvas.probes" (dict "root" $root "name" "pg-gvm") | nindent 2 }}
  {{- include "openvas.resources" (dict "root" $root "name" "pg-gvm") | nindent 2 }}
  lifecycle:
    postStart:
      exec:
        command: ["/bin/sh", "-c", "chown -R postgres:postgres /var/lib/postgresql"]
{{- end }}
