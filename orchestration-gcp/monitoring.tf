resource "google_cloud_run_v2_service_iam_member" "uptime_access_to_orch" {
  name     = google_cloud_run_v2_service.orchestration.name
  location = var.region
  role     = "roles/run.invoker"
  member   = "serviceAccount:service-${data.google_project.zipline.number}@gcp-sa-monitoring-notification.iam.gserviceaccount.com"

  depends_on = [
    google_cloud_run_v2_service.orchestration
  ]
}

resource "google_cloud_run_v2_service_iam_member" "uptime_access_to_ui" {
  name     = google_cloud_run_v2_service.zipline_ui.name
  location = var.region
  role     = "roles/run.invoker"
  member   = "serviceAccount:service-${data.google_project.zipline.number}@gcp-sa-monitoring-notification.iam.gserviceaccount.com"

  depends_on = [
    google_cloud_run_v2_service.zipline_ui
  ]
}

resource "google_monitoring_uptime_check_config" "orch_uptime_check" {
  display_name = "Zipline Orchestration ${title(var.name_prefix)} Uptime Check"
  timeout      = "10s"
  period       = "300s"

  http_check {
    path         = "/ping"
    port         = 443
    use_ssl      = true
    validate_ssl = false
    accepted_response_status_codes {
      status_class = "STATUS_CLASS_2XX"
    }
    service_agent_authentication {
      type = "OIDC_TOKEN"
    }
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = data.google_project.zipline.project_id
      host       = trimprefix(google_cloud_run_v2_service.orchestration.uri, "https://")
    }
  }

  depends_on = [
    google_cloud_run_v2_service.orchestration,
    google_cloud_run_v2_service_iam_member.uptime_access_to_orch
  ]
}

resource "google_monitoring_uptime_check_config" "ui_uptime_check" {
  display_name = "Zipline UI ${title(var.name_prefix)} Uptime Check"
  timeout      = "10s"
  period       = "300s"

  http_check {
    port         = 443
    use_ssl      = true
    validate_ssl = false
    accepted_response_status_codes {
      status_class = "STATUS_CLASS_2XX"
    }
    service_agent_authentication {
      type = "OIDC_TOKEN"
    }
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = data.google_project.zipline.project_id
      host       = trimprefix(google_cloud_run_v2_service.zipline_ui.uri, "https://")
    }
  }

  depends_on = [
    google_cloud_run_v2_service.zipline_ui,
    google_cloud_run_v2_service_iam_member.uptime_access_to_ui
  ]
}

resource "google_monitoring_notification_channel" "alert_email" {
  display_name = "Zipline ${title(var.name_prefix)} Alerts"
  description  = "Email notifications for uptime check failures"
  type         = "email"
  labels = {
    email_address = var.alerting_email
  }
  force_delete = false
}

resource "google_monitoring_alert_policy" "orch_uptime_alert" {
  display_name = "Zipline Orchestration Service for ${title(var.name_prefix)} Down Alert"
  combiner     = "OR"

  conditions {
    display_name = "Orchestration Uptime Check Failure"

    condition_threshold {
      filter = join(" AND ", [
        "resource.type=\"uptime_url\"",
        "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\"",
        "resource.labels.project_id=\"${data.google_project.zipline.project_id}\"",
        "resource.labels.host=\"${trimprefix(google_cloud_run_v2_service.orchestration.uri, "https://")}\""
      ])
      duration        = "300s" # Alert after 5 minute of failure
      comparison      = "COMPARISON_LT"
      threshold_value = 1

      trigger {
        count = 1
      }

      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_FRACTION_TRUE"
        cross_series_reducer = "REDUCE_MEAN"
        group_by_fields = [
          "resource.labels.project_id",
          "resource.labels.host"
        ]
      }
    }
  }

  # Send notifications to email
  notification_channels = [
    google_monitoring_notification_channel.alert_email.name
  ]

  # Optional: Documentation for the alert
  documentation {
    content   = "The Zipline Orchestration Service for ${title(var.name_prefix)} uptime check has failed for at least 5 minutes. Please investigate the service availability."
    mime_type = "text/markdown"
  }

  # Alert when resolved as well
  alert_strategy {
    auto_close = "3600s" # Auto-close after 1 hour if resolved
  }

  depends_on = [
    google_monitoring_uptime_check_config.orch_uptime_check
  ]
}

# Create alert policy for UI uptime check (if you have one)
resource "google_monitoring_alert_policy" "ui_uptime_alert" {
  display_name = "Zipline UI Service for ${title(var.name_prefix)} Down Alert"
  combiner     = "OR"

  conditions {
    display_name = "UI Uptime Check Failure"

    condition_threshold {
      filter = join(" AND ", [
        "resource.type=\"uptime_url\"",
        "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\"",
        "resource.labels.project_id=\"${data.google_project.zipline.project_id}\"",
        "resource.labels.host=\"${trimprefix(google_cloud_run_v2_service.zipline_ui.uri, "https://")}\""

      ])
      duration        = "300s"
      comparison      = "COMPARISON_LT"
      threshold_value = 1

      trigger {
        count = 1
      }

      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_FRACTION_TRUE"
        cross_series_reducer = "REDUCE_MEAN"
        group_by_fields = [
          "resource.labels.project_id",
          "resource.labels.host"
        ]
      }
    }
  }

  notification_channels = [
    google_monitoring_notification_channel.alert_email.name
  ]

  documentation {
    content   = "The Zipline UI service for ${title(var.name_prefix)} uptime check has failed for at least 5 minutes. Please investigate the service availability."
    mime_type = "text/markdown"
  }

  alert_strategy {
    auto_close = "3600s"
  }

  depends_on = [
    google_monitoring_uptime_check_config.ui_uptime_check
  ]
}
