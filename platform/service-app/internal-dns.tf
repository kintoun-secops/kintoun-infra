# =======================================================
# 서비스 VPC 전용 프라이빗 영역
# =======================================================
resource "aws_route53_zone" "internal" {
  name = var.internal_zone_name

  vpc {
    vpc_id = local.vpc_id
  }

  tags = {
    Name      = "${var.project_name}-service-internal"
    ManagedBy = "Terraform"
  }
}

resource "aws_route53_record" "ci_internal" {
  zone_id = aws_route53_zone.internal.zone_id
  name    = "ci.${var.internal_zone_name}"
  type    = "A"
  ttl     = 60
  records = [aws_instance.ci.private_ip]
}
