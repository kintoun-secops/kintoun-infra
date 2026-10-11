# =======================================================
# 기존 호스팅 영역 조회
# =======================================================
data "aws_route53_zone" "main" {
  name         = var.hosted_zone_name
  private_zone = false
}

# =======================================================
# ACM 인증서 요청
# =======================================================
resource "aws_acm_certificate" "main" {
  domain_name       = var.service_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name      = "${var.project_name}-service-certificate"
    ManagedBy = "Terraform"
  }
}

# =======================================================
# ACM 검증용 DNS 레코드
# =======================================================
resource "aws_route53_record" "acm_validation" {
  for_each = {
    for option in aws_acm_certificate.main.domain_validation_options :
    option.domain_name => {
      name   = option.resource_record_name
      type   = option.resource_record_type
      record = option.resource_record_value
    }
  }

  allow_overwrite = true
  zone_id         = data.aws_route53_zone.main.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 300
}

resource "aws_acm_certificate_validation" "main" {
  certificate_arn = aws_acm_certificate.main.arn

  validation_record_fqdns = [
    for record in aws_route53_record.acm_validation :
    record.fqdn
  ]
}

# =======================================================
# 서비스 도메인을 ALB 에 연결
# =======================================================
resource "aws_route53_record" "service" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.service_domain
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}

# =======================================================
# php 인증서 (기존 인증서는 두고 리스너에 추가로 붙인다)
# =======================================================
resource "aws_acm_certificate" "php" {
  domain_name       = var.php_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name      = "${var.project_name}-service-php-certificate"
    ManagedBy = "Terraform"
  }
}

resource "aws_route53_record" "php_acm_validation" {
  for_each = {
    for option in aws_acm_certificate.php.domain_validation_options :
    option.domain_name => {
      name   = option.resource_record_name
      type   = option.resource_record_type
      record = option.resource_record_value
    }
  }

  allow_overwrite = true
  zone_id         = data.aws_route53_zone.main.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 300
}

resource "aws_acm_certificate_validation" "php" {
  certificate_arn = aws_acm_certificate.php.arn

  validation_record_fqdns = [
    for record in aws_route53_record.php_acm_validation :
    record.fqdn
  ]
}

resource "aws_lb_listener_certificate" "php" {
  listener_arn    = aws_lb_listener.https.arn
  certificate_arn = aws_acm_certificate_validation.php.certificate_arn
}

# =======================================================
# php 도메인을 ALB 에 연결
# =======================================================
resource "aws_route53_record" "php" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.php_domain
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}
