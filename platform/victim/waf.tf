# =======================================================
# WAF Web ACL (Regional — ALB 용)
# =======================================================
resource "aws_wafv2_web_acl" "main" { # WAF의 핵심 리소스, 규칙들을 모아놓은 방화벽 정책 세트
  name        = "${var.project_name}-waf"
  description = "Victim Server ALB Protect WAF"
  scope       = "REGIONAL" # ALB나 API Gateway처럼 특정 리전에 있는 리소스를 보호 할 때 쓴다.
  # CloudFront 처럼 전세계 단위면 CLOUDFRONT를 써야 한다.

  default_action {
    allow {} # 아래에 선언한 규칙 어디에도 안걸리면 기본적으로 통과
  }

  rule {
    name     = "AWS-KnownBadInputsRuleSet" # 이 규칙의 이름표
    priority = 1                           # 요청이 들어오면 어떤 순서로 검사할지 정함(규칙이 여러 개 일 때) 1번에서 걸리면 걸려온 요청 즉시 막고 뒤에 있는 규칙은 검사 X

    override_action { # 규칙 대로 막겠다는 뜻 count {}로 바꾸면 규칙에 걸리긴 하지만 차단하지 않고 개수만 세고 통과 시킨다.
      none {}         # Log4shell 시나리오에서 403 뜬 이유가 none 이다.
    }

    statement {                                              # 규칙이 무엇을 검사할지 정의하는 부분
      managed_rule_group_statement {                         # AWS가 미리 만들어둔 규칙 묶음을 통째로 가져다 쓰겠다는 뜻
        name        = "AWSManagedRulesKnownBadInputsRuleSet" # AWS가 미리 만들어둔 규칙그룹의 정확한 이름
        vendor_name = "AWS"                                  # 이 규칙 묶음을 누가 만들었는지, AWS 자체 제공 규칙이라 항상 "AWS"
      }
    }

    visibility_config {                               # visibility_config 는 필수 항목이다.
      cloudwatch_metrics_enabled = false              # CloudWatch에서 이 규칙 전용 그래프를 볼 수 있게 한다.
      metric_name                = "known-bad-inputs" # 그 그래프의 이름표
      sampled_requests_enabled   = false              # 이 규칙에 걸린 요청 중 일부 샘플을 WAF 콘솔에서 볼 수 있게 저장
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = false
    metric_name                = "${var.project_name}-waf"
    sampled_requests_enabled   = false
  }

  tags = {
    Name     = "${var.project_name}-waf"
    ManageBy = "Terraform"
  }
}

# =======================================================
# WAF Web ACL <-> ALB 연결
# (web.tf 에서 이 프로젝트가 직접 만드는 ALB를 보호 대상으로 지정)
# =======================================================
resource "aws_wafv2_web_acl_association" "victim" {
  resource_arn = aws_lb.alb.arn             # 보호 대상: web.tf가 생성한 실제 ALB
  web_acl_arn  = aws_wafv2_web_acl.main.arn # 적용할 WAF 규칙 세트 
}