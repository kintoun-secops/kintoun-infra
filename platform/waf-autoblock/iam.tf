# =======================================================
# Lambda 로그(CloudWatch Logs)를 Wazuh가 읽을 수 있게 하는 권한정책
# GuardDuty 모듈과 동일한 패턴: 소비하는 루트에서 정책을 만들어
# platform/wazuh의 Wazuh Role에 붙인다
# =======================================================
data "aws_iam_policy_document" "waf_autoblock_logging_wazuh" {
  statement {
    sid     = "DescribeLogStreams"
    effect  = "Allow"
    actions = ["logs:DescribeLogStreams"]
    resources = [
      "${aws_cloudwatch_log_group.lambda.arn}:*"
    ]
  }

  statement {
    sid     = "GetLogEvents"
    effect  = "Allow"
    actions = ["logs:GetLogEvents"]
    resources = [
      "${aws_cloudwatch_log_group.lambda.arn}:log-stream:*"
    ]
  }
}

resource "aws_iam_policy" "waf_autoblock_logging_wazuh" {
  name        = "${var.project_name}-waf-autoblock-logging-for-wazuh"
  description = "Lambda(waf-autoblock) CloudWatch Logs  Wazuh reading"
  policy      = data.aws_iam_policy_document.waf_autoblock_logging_wazuh.json

  tags = {
    Name      = "${var.project_name}-waf-autoblock-logging-for-wazuh"
    ManagedBy = "Terraform"
  }
}

resource "aws_iam_role_policy_attachment" "waf_autoblock_logging_wazuh" {
  role       = local.wazuh_role
  policy_arn = aws_iam_policy.waf_autoblock_logging_wazuh.arn
}