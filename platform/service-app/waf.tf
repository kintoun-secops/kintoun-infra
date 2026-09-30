# =======================================================
# WAF Web ACL (Regional — ALB 용, 규칙 없음 / 빈 WAF)
# =======================================================
resource "aws_wafv2_web_acl" "main" {
  name        = "${var.project_name}-service-waf"
  description = "Service App ALB Protect WAF"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = false
    metric_name                = "${var.project_name}-service-waf"
    sampled_requests_enabled   = false
  }

  tags = {
    Name      = "${var.project_name}-service-waf"
    ManagedBy = "Terraform"
  }
}

# =======================================================
# WAF Web ACL <-> ALB 연결
# =======================================================
resource "aws_wafv2_web_acl_association" "main" {
  resource_arn = aws_lb.main.arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}