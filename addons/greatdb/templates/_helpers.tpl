{{/*
Expand the name of the chart.
*/}}
{{- define "greatdb.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "greatdb.selectorLabels" -}}
app.kubernetes.io/name: {{ include "greatdb.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "greatdb.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "greatdb.labels" -}}
helm.sh/chart: {{ include "greatdb.chart" . }}
{{ include "greatdb.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Define image
*/}}
{{- define "greatdb.repository" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}
{{- end }}

{{- define "greatdb.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:{{ .Values.image.tag }}
{{- end }}

{{- define "exporter.repository" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.prom.exporter.repository}}
{{- end }}

{{- define "exporter.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.prom.exporter.repository}}:{{.Values.image.prom.exporter.tag}}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "greatdb.annotations" -}}
{{ include "kblib.helm.resourcePolicy" . }}
{{ include "greatdb.apiVersion" . }}
{{- end }}

{{/*
API version annotation
*/}}
{{- define "greatdb.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}

{{/*
Define greatdb component definition name
*/}}
{{- define "greatdb.cmpdName" -}}
greatdb-{{ .Chart.Version }}
{{- end -}}

{{/*
Define greatdb component definition regular expression name prefix
*/}}
{{- define "greatdb.cmpdRegexpPattern" -}}
^greatdb-
{{- end -}}
