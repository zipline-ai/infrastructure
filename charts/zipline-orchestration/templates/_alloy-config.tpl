{{- define "zipline-orchestration.alloyConfig" -}}
discovery.kubernetes "pods" {
  role = "pod"
}

discovery.relabel "pods" {
  targets = discovery.kubernetes.pods.targets

  rule {
    source_labels = ["__meta_kubernetes_namespace"]
    action        = "drop"
    regex         = "kube-system|kube-public|kube-node-lease|cert-manager|default"
  }

  rule {
    source_labels = ["__meta_kubernetes_pod_controller_name"]
    regex         = "([0-9a-z-.]+?)(-[0-9a-f]{8,10})?"
    target_label  = "__tmp_controller_name"
  }

  rule {
    source_labels = ["__meta_kubernetes_pod_label_app_kubernetes_io_name", "__meta_kubernetes_pod_label_app", "__tmp_controller_name", "__meta_kubernetes_pod_name"]
    regex         = "^;*([^;]+)(;.*)?$"
    target_label  = "app"
  }

  rule {
    source_labels = ["__meta_kubernetes_pod_label_app_kubernetes_io_instance", "__meta_kubernetes_pod_label_instance"]
    regex         = "^;*([^;]+)(;.*)?$"
    target_label  = "instance"
  }

  rule {
    source_labels = ["__meta_kubernetes_pod_label_app_kubernetes_io_component", "__meta_kubernetes_pod_label_component"]
    regex         = "^;*([^;]+)(;.*)?$"
    target_label  = "component"
  }

  rule {
    source_labels = ["__meta_kubernetes_namespace", "app"]
    separator     = "/"
    target_label  = "job"
  }
  {{- range $label, $source := dict "namespace" "namespace" "node_name" "pod_node_name" "pod" "pod_name" "container" "pod_container_name" "chronon_job_id" "pod_label_chronon_job_id" "spark_role" "pod_label_chronon_spark_role" }}
  rule {
    source_labels = [{{ printf "__meta_kubernetes_%s" $source | quote }}]
    target_label  = {{ $label | quote }}
  }
  {{- end }}
}

loki.source.kubernetes "pods" {
  targets    = discovery.relabel.pods.output
  forward_to = [loki.process.pods.receiver]
}

loki.process "pods" {
  forward_to = [loki.write.local.receiver]

  stage.json {
    expressions = { workflowId = "workflowId", stepId = "stepId" }
  }

  stage.structured_metadata {
    values = { workflowId = "workflowId", stepId = "stepId" }
  }
}

loki.write "local" {
  endpoint {
    url = {{ . | quote }}
  }
}
{{- end -}}
