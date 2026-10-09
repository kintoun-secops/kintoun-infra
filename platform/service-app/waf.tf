# =======================================================
# WAF 로그 테스트용 IP Set
# =======================================================
resource "aws_wafv2_ip_set" "block_test" {
  name               = "${var.project_name}-block-test-ip"
  description        = "Temporary block rule for WAF log ingestion test"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = ["61.77.198.167/32"] # 박윤하의 데스크톱 IP
}
# =======================================================
# 자동 차단용 IP Set (Lambda가 관리)
# 주소 목록은 Lambda 가 바꾸므로 Terraform 은 건드리지 않는다.
# =======================================================
resource "aws_wafv2_ip_set" "auto_block" {
  name               = "${var.project_name}-auto-block-ip"
  description        = "IPs blocked automatically by Wazuh/Lambda managed outside Terraform"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = []

  lifecycle {
    ignore_changes = [addresses]
  }

  tags = {
    Name      = "${var.project_name}-auto-block-ip"
    ManagedBy = "Terraform"
  }
}
# =======================================================
# WAF Web ACL (Regional — ALB 용)
# =======================================================
resource "aws_wafv2_web_acl" "main" {
  name        = "${var.project_name}-service-waf"
  description = "Service App ALB Protect WAF"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "block-auto-ip"
    priority = 0
    action {
      block {}
    }

    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.auto_block.arn
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-block-auto-ip"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "block-test-ip"
    priority = 1
    action {
      block {}
    }

    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.block_test.arn
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = false
      metric_name                = "${var.project_name}-block-test-ip"
      sampled_requests_enabled   = false
    }
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