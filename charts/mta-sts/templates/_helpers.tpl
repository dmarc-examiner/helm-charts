{{- define "mta-sts.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "mta-sts.fullname" -}}
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

{{- define "mta-sts.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "mta-sts.labels" -}}
helm.sh/chart: {{ include "mta-sts.chart" . }}
{{ include "mta-sts.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "mta-sts.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mta-sts.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "mta-sts.image" -}}
{{- if .Values.image.digest }}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest }}
{{- else }}
{{- printf "%s:%s" .Values.image.repository .Values.image.tag }}
{{- end }}
{{- end }}

{{- define "mta-sts.tlsSecretName" -}}
{{- default (printf "%s-tls" (include "mta-sts.fullname" .)) .Values.ingress.tls.secretName }}
{{- end }}

{{/*
Effective settings of one domain: the domain entry merged over the chart defaults.
Usage: include "mta-sts.domain" (dict "root" $ "domain" $domain) | fromYaml
*/}}
{{- define "mta-sts.domain" -}}
{{- $root := .root }}
{{- $d := .domain }}
{{- $name := lower $d.name }}
{{- $mode := default $root.Values.policy.mode $d.mode }}
{{- $maxAge := default $root.Values.policy.maxAge $d.maxAge }}
{{- $mx := default $root.Values.policy.mx $d.mx }}
{{- $rua := list }}
{{- range (default $root.Values.tlsRpt.rua $d.tlsRptRua) }}
{{- $rua = append $rua (replace "{domain}" $name .) }}
{{- end }}
{{- if and (ne $mode "none") (empty $mx) }}
{{- fail (printf "domain %s: policy.mx needs at least one MX host when mode is %s" $name $mode) }}
{{- end }}
name: {{ $name }}
host: {{ printf "mta-sts.%s" $name }}
mode: {{ $mode }}
maxAge: {{ int64 $maxAge }}
mx: {{ toJson $mx }}
rua: {{ toJson $rua }}
{{- end }}

{{/*
Policy file body (RFC 8461 section 3.2).
*/}}
{{- define "mta-sts.policy" -}}
version: STSv1
mode: {{ .mode }}
{{- range .mx }}
mx: {{ . }}
{{- end }}
max_age: {{ int64 .maxAge }}
{{ end }}

{{/*
Policy id: changes whenever the policy body changes, so senders refetch it.
*/}}
{{- define "mta-sts.policyId" -}}
{{- include "mta-sts.policy" . | sha256sum | trunc 20 }}
{{- end }}
