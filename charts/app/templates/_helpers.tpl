{{/*
App name — required.
*/}}
{{- define "app.name" -}}
{{- required "name is required" .Values.name -}}
{{- end -}}

{{/*
Image repository — defaults to app name if not set.
*/}}
{{- define "app.repository" -}}
{{- .Values.image.repository | default .Values.name -}}
{{- end -}}

{{/*
Full image reference.
*/}}
{{- define "app.image" -}}
{{- if .Values.image.registry -}}
{{ .Values.image.registry }}/{{ include "app.repository" . }}:{{ .Values.image.tag }}
{{- else -}}
{{ include "app.repository" . }}:{{ .Values.image.tag }}
{{- end -}}
{{- end -}}

{{/*
Service target port — defaults to container port.
*/}}
{{- define "app.targetPort" -}}
{{- .Values.service.targetPort | default .Values.port -}}
{{- end -}}

{{/*
Common labels.
*/}}
{{- define "app.labels" -}}
app: {{ include "app.name" . }}
{{- end -}}
