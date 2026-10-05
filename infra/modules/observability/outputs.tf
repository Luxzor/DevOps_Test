output "alarm_topic_arn" {
  value = aws_sns_topic.alarms.arn
}

output "alarm_name_prefix" {
  description = "Prefijo que usa el pipeline para vigilar las alarmas después de desplegar."
  value       = var.name
}

output "dashboard_name" {
  value = aws_cloudwatch_dashboard.this.dashboard_name
}
