locals {
  ui_logs_freshness_settings = {
    low_cost = {
      schedule         = "rate(30 minutes)"
      lookback_minutes = 30
    }
    balanced = {
      schedule         = "rate(5 minutes)"
      lookback_minutes = 5
    }
    fresh = {
      schedule         = "rate(1 minute)"
      lookback_minutes = 1
    }
  }

  lambda_role_name         = "${var.name_prefix}-datasource-ingestor"
  ui_logs_lambda_name      = "${var.name_prefix}-ui-log-ingestor"
  ui_logs_log_group_name   = var.ui_logs_log_group_name != "" ? var.ui_logs_log_group_name : "/aws/eks/${var.name_prefix}-eks/containers"
  ui_logs_schedule         = local.ui_logs_freshness_settings[var.ui_logs_freshness_profile].schedule
  ui_logs_lookback_minutes = local.ui_logs_freshness_settings[var.ui_logs_freshness_profile].lookback_minutes
}
