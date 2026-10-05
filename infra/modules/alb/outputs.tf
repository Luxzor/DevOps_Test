output "dns_name" {
  value = aws_lb.this.dns_name
}

output "security_group_id" {
  value = aws_security_group.alb.id
}

output "target_group_arn" {
  value = aws_lb_target_group.app.arn
}

output "arn_suffix" {
  description = "Dimensión LoadBalancer de las métricas de CloudWatch."
  value       = aws_lb.this.arn_suffix
}

output "target_group_arn_suffix" {
  description = "Dimensión TargetGroup de las métricas de CloudWatch."
  value       = aws_lb_target_group.app.arn_suffix
}

output "url" {
  value = local.https_enabled ? "https://${aws_lb.this.dns_name}" : "http://${aws_lb.this.dns_name}${var.listener_port == 80 ? "" : ":${var.listener_port}"}"
}
