locals {
  https_enabled = var.certificate_arn != null
}

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "Trafico publico hacia el balanceador de ${var.name}"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-alb" }
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  #checkov:skip=CKV_AWS_260:Balanceador público; con certificado, HTTP solo redirige a HTTPS.
  security_group_id = aws_security_group.alb.id
  description       = "HTTP desde Internet"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = var.listener_port
  to_port           = var.listener_port
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  count             = local.https_enabled ? 1 : 0
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS desde Internet"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

data "aws_vpc" "this" {
  id = var.vpc_id
}

# El ALB solo puede hablar con las tareas, dentro de la VPC y en el puerto del contenedor.
resource "aws_vpc_security_group_egress_rule" "to_targets" {
  security_group_id = aws_security_group.alb.id
  description       = "Hacia las tareas de ECS"
  cidr_ipv4         = data.aws_vpc.this.cidr_block
  ip_protocol       = "tcp"
  from_port         = var.container_port
  to_port           = var.container_port
}

resource "aws_lb" "this" {
  #checkov:skip=CKV_AWS_91:Access logs a S3 quedan como paso de crecimiento (requieren bucket dedicado).
  #checkov:skip=CKV2_AWS_28:WAF fuera del alcance del proyecto.
  name                       = "${var.name}-alb"
  load_balancer_type         = "application"
  internal                   = false
  security_groups            = [aws_security_group.alb.id]
  subnets                    = var.public_subnet_ids
  drop_invalid_header_fields = true
  enable_deletion_protection = var.deletion_protection
}

resource "aws_lb_target_group" "app" {
  #checkov:skip=CKV_AWS_378:TLS termina en el ALB; el tramo ALB-tarea es tráfico privado dentro de la VPC.
  name        = "${var.name}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  target_type = "ip" # obligatorio con Fargate (modo de red awsvpc)
  vpc_id      = var.vpc_id

  # Tiempo que el ALB espera a que terminen las peticiones en curso antes de quitar una tarea.
  deregistration_delay = 30

  health_check {
    path                = var.health_check_path
    matcher             = "200"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "http" {
  #checkov:skip=CKV_AWS_2:HTTP solo sin certificado (simulación); con certificado redirige a HTTPS.
  #checkov:skip=CKV_AWS_103:TLS se aplica en el listener HTTPS cuando hay certificado.
  #checkov:skip=CKV2_AWS_20:Igual que el anterior: la redirección se activa con certificate_arn.
  load_balancer_arn = aws_lb.this.arn
  port              = var.listener_port
  protocol          = "HTTP"

  default_action {
    type             = local.https_enabled ? "redirect" : "forward"
    target_group_arn = local.https_enabled ? null : aws_lb_target_group.app.arn

    dynamic "redirect" {
      for_each = local.https_enabled ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }
}

resource "aws_lb_listener" "https" {
  count             = local.https_enabled ? 1 : 0
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
