{{- define "webmethods-msr.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "webmethods-msr.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{- define "webmethods-msr.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "webmethods-msr.labels" -}}
helm.sh/chart: {{ include "webmethods-msr.chart" . }}
{{ include "webmethods-msr.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "webmethods-msr.selectorLabels" -}}
app: {{ include "webmethods-msr.fullname" . }}
app.kubernetes.io/name: {{ include "webmethods-msr.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Values.clusterLabel }}
cluster: {{ .Values.clusterLabel }}
{{- end }}
{{- end }}
