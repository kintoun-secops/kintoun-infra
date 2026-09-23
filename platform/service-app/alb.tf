# =======================================================
# ALB 생성
# =======================================================
resource "aws_lb" "main" {
  name                       = "${var.project_name}-service-alb"
  internal                   = false
  load_balancer_type         = "application"
  drop_invalid_header_fields = true

  security_groups = [local.alb_sg_id]
  subnets         = values(local.public_subnet_ids)

  tags = {
    Name      = "${var.project_name}-service-alb"
    ManagedBy = "Terraform"
  }
}

# =======================================================
# 프론트 타겟 그룹
# =======================================================
resource "aws_lb_target_group" "frontend" {
  name        = "${var.project_name}-service-frontend-tg"
  port        = local.frontend_app_port
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = local.vpc_id

  health_check {
    enabled             = true
    path                = var.frontend_health_path
    protocol            = "HTTP"
    port                = "traffic-port"
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
  }

  tags = {
    Name      = "${var.project_name}-service-frontend-tg"
    ManagedBy = "Terraform"
  }
}

resource "aws_lb_target_group_attachment" "frontend" {
  target_group_arn = aws_lb_target_group.frontend.arn
  target_id        = aws_instance.frontend.id
  port             = local.frontend_app_port
}

# =======================================================
# 백엔드 타겟 그룹
# =======================================================
resource "aws_lb_target_group" "backend" {
  name        = "${var.project_name}-service-backend-tg"
  port        = local.backend_app_port
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = local.vpc_id

  health_check {
    enabled             = true
    path                = var.backend_health_path
    protocol            = "HTTP"
    port                = "traffic-port"
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
  }

  tags = {
    Name      = "${var.project_name}-service-backend-tg"
    ManagedBy = "Terraform"
  }
}

resource "aws_lb_target_group_attachment" "backend" {
  target_group_arn = aws_lb_target_group.backend.arn
  target_id        = aws_instance.backend.id
  port             = local.backend_app_port
}

# =======================================================
# HTTP -> HTTPS Redirect
# =======================================================
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      protocol    = "HTTPS"
      port        = "443"
      status_code = "HTTP_301"
    }
  }
}

# =======================================================
# HTTPS 리스너
# =======================================================
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  certificate_arn = aws_acm_certificate_validation.main.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

resource "aws_lb_listener_rule" "api" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 100

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  tags = {
    Name      = "${var.project_name}-service-api-rule"
    ManagedBy = "Terraform"
  }
}
