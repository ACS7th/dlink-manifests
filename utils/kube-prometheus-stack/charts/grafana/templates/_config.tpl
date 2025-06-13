{{/*
 Generate config map data
 */}}
{{- define "grafana.configData" -}}
{{ include "grafana.assertNoLeakedSecrets" . }}
{{- $files := .Files }}
{{- $root := . -}}
{{- with .Values.plugins }}
plugins: {{ join "," . }}
{{- end }}
grafana.ini: |
{{- range $elem, $elemVal := index .Values "grafana.ini" }}
  {{- if not (kindIs "map" $elemVal) }}
  {{- if kindIs "invalid" $elemVal }}
  {{ $elem }} =
  {{- else if kindIs "slice" $elemVal }}
  {{ $elem }} = {{ toJson $elemVal }}
  {{- else if kindIs "string" $elemVal }}
  {{ $elem }} = {{ tpl $elemVal $ }}
  {{- else }}
  {{ $elem }} = {{ $elemVal }}
  {{- end }}
  {{- end }}
{{- end }}
{{- range $key, $value := index .Values "grafana.ini" }}
  {{- if kindIs "map" $value }}
  [{{ $key }}]
  {{- range $elem, $elemVal := $value }}
  {{- if kindIs "invalid" $elemVal }}
  {{ $elem }} =
  {{- else if kindIs "slice" $elemVal }}
  {{ $elem }} = {{ toJson $elemVal }}
  {{- else if kindIs "string" $elemVal }}
  {{ $elem }} = {{ tpl $elemVal $ }}
  {{- else }}
  {{ $elem }} = {{ $elemVal }}
  {{- end }}
  {{- end }}
  {{- end }}
{{- end }}

{{- range $key, $value := .Values.datasources }}
{{- if not (hasKey $value "secret") }}
{{ $key }}: |
  {{- tpl (toYaml $value | nindent 2) $root }}
{{- end }}
{{- end }}

{{- range $key, $value := .Values.notifiers }}
{{- if not (hasKey $value "secret") }}
{{ $key }}: |
  {{- toYaml $value | nindent 2 }}
{{- end }}
{{- end }}

{{- range $key, $value := .Values.alerting }}
{{- if (hasKey $value "file") }}
{{ $key }}:
{{- toYaml ( $files.Get $value.file ) | nindent 2 }}
{{- else if (or (hasKey $value "secret") (hasKey $value "secretFile"))}}
{{/*  will be stored inside secret generated by "configSecret.yaml"*/}}
{{- else }}
{{ $key }}: |
  {{- tpl (toYaml $value | nindent 2) $root }}
{{- end }}
{{- end }}

{{- range $key, $value := .Values.dashboardProviders }}
{{ $key }}: |
  {{- toYaml $value | nindent 2 }}
{{- end }}

{{- if .Values.dashboards  }}
download_dashboards.sh: |
  #!/usr/bin/env sh
  set -euf
  {{- if .Values.dashboardProviders }}
    {{- range $key, $value := .Values.dashboardProviders }}
      {{- range $value.providers }}
  mkdir -p {{ .options.path }}
      {{- end }}
    {{- end }}
  {{- end }}
{{ $dashboardProviders := .Values.dashboardProviders }}
{{- range $provider, $dashboards := .Values.dashboards }}
  {{- range $key, $value := $dashboards }}
    {{- if (or (hasKey $value "gnetId") (hasKey $value "url")) }}
  curl -skf \
  --connect-timeout 60 \
  --max-time 60 \
    {{- if not $value.b64content }}
      {{- if not $value.acceptHeader }}
  -H "Accept: application/json" \
      {{- else }}
  -H "Accept: {{ $value.acceptHeader }}" \
      {{- end }}
      {{- if $value.token }}
  -H "Authorization: token {{ $value.token }}" \
      {{- end }}
      {{- if $value.bearerToken }}
  -H "Authorization: Bearer {{ $value.bearerToken }}" \
      {{- end }}
      {{- if $value.basic }}
  -H "Authorization: Basic {{ $value.basic }}" \
      {{- end }}
      {{- if $value.gitlabToken }}
  -H "PRIVATE-TOKEN: {{ $value.gitlabToken }}" \
      {{- end }}
  -H "Content-Type: application/json;charset=UTF-8" \
    {{- end }}
  {{- $dpPath := "" -}}
  {{- range $kd := (index $dashboardProviders "dashboardproviders.yaml").providers }}
    {{- if eq $kd.name $provider }}
    {{- $dpPath = $kd.options.path }}
    {{- end }}
  {{- end }}
  {{- if $value.url }}
    "{{ $value.url }}" \
  {{- else }}
    "https://grafana.com/api/dashboards/{{ $value.gnetId }}/revisions/{{- if $value.revision -}}{{ $value.revision }}{{- else -}}1{{- end -}}/download" \
  {{- end }}
  {{- if $value.datasource }}
    {{- if kindIs "string" $value.datasource }}
    | sed '/-- .* --/! s/"datasource":.*,/"datasource": "{{ $value.datasource }}",/g' \
    {{- end }}
    {{- if kindIs "slice" $value.datasource }}
      {{- range $value.datasource }}
        | sed '/-- .* --/! s/${{"{"}}{{ .name }}}/{{ .value }}/g' \
      {{- end }}
    {{- end }}
  {{- end }}
  {{- if $value.b64content }}
    | base64 -d \
  {{- end }}
  > "{{- if $dpPath -}}{{ $dpPath }}{{- else -}}/var/lib/grafana/dashboards/{{ $provider }}{{- end -}}/{{ $key }}.json"
    {{ end }}
  {{- end }}
{{- end }}
{{- end }}
{{- end -}}

{{/*
 Generate dashboard json config map data
 */}}
{{- define "grafana.configDashboardProviderData" -}}
provider.yaml: |-
  apiVersion: 1
  providers:
    - name: '{{ .Values.sidecar.dashboards.provider.name }}'
      orgId: {{ .Values.sidecar.dashboards.provider.orgid }}
      {{- if not .Values.sidecar.dashboards.provider.foldersFromFilesStructure }}
      folder: '{{ .Values.sidecar.dashboards.provider.folder }}'
      folderUid: '{{ .Values.sidecar.dashboards.provider.folderUid }}'
      {{- end }}
      type: {{ .Values.sidecar.dashboards.provider.type }}
      disableDeletion: {{ .Values.sidecar.dashboards.provider.disableDelete }}
      allowUiUpdates: {{ .Values.sidecar.dashboards.provider.allowUiUpdates }}
      updateIntervalSeconds: {{ .Values.sidecar.dashboards.provider.updateIntervalSeconds | default 30 }}
      options:
        foldersFromFilesStructure: {{ .Values.sidecar.dashboards.provider.foldersFromFilesStructure }}
        path: {{ .Values.sidecar.dashboards.folder }}{{- with .Values.sidecar.dashboards.defaultFolderName }}/{{ . }}{{- end }}
{{- end -}}

{{- define "grafana.secretsData" -}}
{{- if and (not .Values.env.GF_SECURITY_DISABLE_INITIAL_ADMIN_CREATION) (not .Values.admin.existingSecret) (not .Values.env.GF_SECURITY_ADMIN_PASSWORD__FILE) (not .Values.env.GF_SECURITY_ADMIN_PASSWORD) }}
admin-user: {{ .Values.adminUser | b64enc | quote }}
{{- if .Values.adminPassword }}
admin-password: {{ .Values.adminPassword | b64enc | quote }}
{{- else }}
admin-password: {{ include "grafana.password" . }}
{{- end }}
{{- end }}
{{- if not .Values.ldap.existingSecret }}
ldap-toml: {{ tpl .Values.ldap.config $ | b64enc | quote }}
{{- end }}
{{- end -}}
