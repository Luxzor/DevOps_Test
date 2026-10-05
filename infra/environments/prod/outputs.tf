output "app_url" {
  value = aws_ssm_parameter.app_url.insecure_value
}

output "ecr_repository_url" {
  value = module.ecr.repository_url
}

output "cluster_name" {
  value = module.service.cluster_name
}

output "service_name" {
  value = module.service.service_name
}

output "dashboard_name" {
  value = module.observability.dashboard_name
}

output "alarm_topic_arn" {
  value = module.observability.alarm_topic_arn
}
