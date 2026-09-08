# 웹 접속을 위한 ALB 및 DNS 설정

# =======================================================
# ALB 생성
# =======================================================
resource "aws_lb" "alb" {
  name                       = "${var.project_name}-alb"
  internal                   = false # 인터넷과 연결(Public) / true(VPC 내부, Private)
  load_balancer_type         = "application"
  drop_invalid_header_fields = true # 로드 밸런서로 들어오는 유효하지 않은 헤더 삭제

  security_groups = [
    aws_security_group.alb_sg.id
  ]
  subnets = [
    for subnet in aws_subnet.alb_public_subnets :
    subnet.id
  ]

  tags = {
    Name     = "${var.project_name}-alb"
    ManageBy = "Terraform"
  }
}
# =======================================================
# ALB가 요청을 전달할 서버 타겟 그룹 생성
# =======================================================
resource "aws_lb_target_group" "alb_tg" {
  name        = "${var.project_name}-alb-tg"
  port        = var.victim_app_port
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = local.main_vpc_id

  health_check {
    enabled             = true
    path                = "/health"
    protocol            = "HTTP"
    port                = "traffic-port" # 대상 서버가 트래픽을 받고 있는 실제 서비스 포트를 그대로 사용
    matcher             = "200-399"      # 헬스체크가 정상이라고 판단할 HTTP 응답코드 범위
    healthy_threshold   = 2              # 비정상이었던 서버가 정상으로 판정받기 위해 연속 성공해야하는 횟수
    unhealthy_threshold = 3              # 정상이었던 서버가 비정상으로 판정받기 위해 연속 실패해야하는 횟수
    interval            = 30             # 초 단위
    timeout             = 5              # 초 단위
  }

  tags = {
    Name     = "${var.project_name}-alb-tg"
    ManageBy = "Terraform"
  }
}

# =======================================================
# ALB 타겟 그룹 등록 (Victim EC2)
# =======================================================
resource "aws_lb_target_group_attachment" "alb_tg_victim" {
  target_group_arn = aws_lb_target_group.alb_tg.arn
  target_id        = aws_instance.victim_ec2.id
  port             = var.victim_app_port
}

# =======================================================
# HTTP -> HTTPS Redirect 설정 (ACM 인증서 먼저 셋팅)
# =======================================================
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
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

# ==================================================================
# ====================== DNS 설정 및 연결 =============================
# ==================================================================

# =======================================================
# ACM을 통해 HTTPS 인증서 요청
# =======================================================
resource "aws_acm_certificate" "victim" {
  domain_name       = var.service_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true # 인증서 갱신 시 기존 인증서 유지하면서 갱신, 갱신 후 기존 인증서 삭제
  }

  tags = {
    Name     = "${var.project_name}-victim-certificate"
    ManageBy = "Terraform"
  }
}

# =======================================================
# 기존에 생성되어 있는 Route 53 호스팅 영역 조회 후 불러오기
# =======================================================
data "aws_route53_zone" "kintoun" {
  name         = var.hosted_zone_name
  private_zone = false
}

# =======================================================
# ACM 검증을 위한 DNS CNAME 레코드 생성
# =======================================================
resource "aws_route53_record" "acm_validation" {
  for_each = {
    for option in aws_acm_certificate.victim.domain_validation_options :
    option.domain_name => {
      name   = option.resource_record_name
      type   = option.resource_record_type
      record = option.resource_record_value
    }
  }
  allow_overwrite = true # 동일한 인증서 검증 레코드가 있으면 갱신(인증서 갱신 및 테라폼 replace 될 때 최신 정보로 덮어씀)
  zone_id         = data.aws_route53_zone.kintoun.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 300
}

# =======================================================
# ACM 인증서 검증 프로세스 완료 및 대기
# =======================================================
resource "aws_acm_certificate_validation" "victim" {
  certificate_arn = aws_acm_certificate.victim.arn
  validation_record_fqdns = [
    for record in aws_route53_record.acm_validation :
    record.fqdn
  ]
}

# =======================================================
# ALB에 도메인 연결
# =======================================================
resource "aws_route53_record" "alb" {
  zone_id = data.aws_route53_zone.kintoun.zone_id
  name    = var.service_domain
  type    = "A"

  alias {
    name                   = aws_lb.alb.dns_name
    zone_id                = aws_lb.alb.zone_id
    evaluate_target_health = true
  }
}

# =======================================================
# 인증서 발급 후, ALB의 HTTPS 리스너에 인증서 연결
# =======================================================
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 443
  protocol          = "HTTPS"

  certificate_arn = aws_acm_certificate_validation.victim.certificate_arn

  # HTTPS 요청을 Target Group으로 전달
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_tg.arn
  }
}