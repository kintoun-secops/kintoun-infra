# =======================================================
# WAF Web ACL (Regional — ALB 용)
# =======================================================
resource "aws_wafv2_web_acl" "main" {
  name        = "${var.project_name}-waf"
  description = "Victim Server ALB Protect WAF"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWS-KnownBadInputsRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = false
      metric_name                = "known-bad-inputs"
      sampled_requests_enabled   = false
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = false
    metric_name                = "${var.project_name}-waf"
    sampled_requests_enabled   = false
  }

  tags = {
    Name     = "${var.project_name}-waf"
    ManagedBy = "Terraform"
  }
}

# =======================================================
# WAF Web ACL <-> ALB 연결
# (web.tf 에서 이 프로젝트가 직접 만드는 ALB를 보호 대상으로 지정)
# =======================================================
resource "aws_wafv2_web_acl_association" "victim" {
  resource_arn = aws_lb.alb.arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}