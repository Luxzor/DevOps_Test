data "aws_region" "current" {}

locals {
  # Métricas propias derivadas de los logs JSON de la app. Funcionan igual en AWS y en el
  # emulador, y miden lo que vive el usuario (status y duración de cada petición).
  namespace = "TasksApi/${var.name}"
}

# ---------- Notificaciones ----------
resource "aws_sns_topic" "alarms" {
  name              = "${var.name}-alarms"
  kms_master_key_id = "alias/aws/sns"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alarm_email == null ? 0 : 1
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# ---------- Métricas a partir de logs ----------
resource "aws_cloudwatch_log_metric_filter" "requests" {
  count          = var.enable_log_metric_filters ? 1 : 0
  name           = "${var.name}-requests"
  log_group_name = var.log_group_name
  pattern        = "{ $.message = \"request\" }"

  metric_transformation {
    name      = "Requests"
    namespace = local.namespace
    value     = "1"
    unit      = "Count"
  }
}

resource "aws_cloudwatch_log_metric_filter" "errors_5xx" {
  count          = var.enable_log_metric_filters ? 1 : 0
  name           = "${var.name}-5xx"
  log_group_name = var.log_group_name
  pattern        = "{ $.message = \"request\" && $.status >= 500 }"

  metric_transformation {
    name      = "Http5xx"
    namespace = local.namespace
    value     = "1"
    unit      = "Count"
  }
}

resource "aws_cloudwatch_log_metric_filter" "latency" {
  count          = var.enable_log_metric_filters ? 1 : 0
  name           = "${var.name}-latency"
  log_group_name = var.log_group_name
  pattern        = "{ $.message = \"request\" }"

  metric_transformation {
    name      = "LatencyMs"
    namespace = local.namespace
    value     = "$.duration_ms"
    unit      = "Milliseconds"
  }
}

# ---------- Alarmas ----------
resource "aws_cloudwatch_metric_alarm" "errors_5xx" {
  alarm_name          = "${var.name}-5xx-errors"
  alarm_description   = "La app respondió más de ${var.error_threshold} errores 5xx por minuto."
  namespace           = local.namespace
  metric_name         = "Http5xx"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 2
  threshold           = var.error_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching" # sin tráfico no hay errores
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
}

resource "aws_cloudwatch_metric_alarm" "latency" {
  alarm_name          = "${var.name}-high-latency"
  alarm_description   = "Latencia promedio mayor a ${var.latency_threshold_ms} ms durante 3 minutos."
  namespace           = local.namespace
  metric_name         = "LatencyMs"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 3
  threshold           = var.latency_threshold_ms
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_targets" {
  alarm_name          = "${var.name}-unhealthy-targets"
  alarm_description   = "El balanceador tiene tareas que no pasan el health check."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "tasks_down" {
  alarm_name          = "${var.name}-tasks-down"
  alarm_description   = "Corren menos tareas que las ${var.desired_count} esperadas."
  namespace           = "ECS/ContainerInsights"
  metric_name         = "RunningTaskCount"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 3
  threshold           = var.desired_count
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "missing"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = var.service_name
  }
}

# ---------- Tablero ----------
resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = var.name
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 8, height = 6
        properties = {
          title   = "Solicitudes por minuto"
          region  = data.aws_region.current.region
          stat    = "Sum"
          period  = 60
          metrics = [[local.namespace, "Requests"]]
        }
      },
      {
        type = "metric", x = 8, y = 0, width = 8, height = 6
        properties = {
          title   = "Errores 5xx por minuto"
          region  = data.aws_region.current.region
          stat    = "Sum"
          period  = 60
          metrics = [[local.namespace, "Http5xx"]]
        }
      },
      {
        type = "metric", x = 16, y = 0, width = 8, height = 6
        properties = {
          title  = "Latencia (ms)"
          region = data.aws_region.current.region
          period = 60
          metrics = [
            [local.namespace, "LatencyMs", { stat = "Average", label = "promedio" }],
            [local.namespace, "LatencyMs", { stat = "p95", label = "p95" }],
          ]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          title   = "Tareas corriendo"
          region  = data.aws_region.current.region
          stat    = "Minimum"
          period  = 60
          metrics = [["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", var.cluster_name, "ServiceName", var.service_name]]
        }
      },
      {
        type = "alarm", x = 12, y = 6, width = 12, height = 6
        properties = {
          title = "Alarmas"
          alarms = [
            aws_cloudwatch_metric_alarm.errors_5xx.arn,
            aws_cloudwatch_metric_alarm.latency.arn,
            aws_cloudwatch_metric_alarm.unhealthy_targets.arn,
            aws_cloudwatch_metric_alarm.tasks_down.arn,
          ]
        }
      },
    ]
  })
}
