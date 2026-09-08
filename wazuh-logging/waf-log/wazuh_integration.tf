# =======================================================
# wazuh_role에 WAF 로그 읽기 권한 추가
# (platform/wazuh 의 기존 wazuh_role 재사용, 새 역할 안 만듦)
# =======================================================
data "aws_iam_policy_document" "wazuh_waf_read" {
  statement {
    sid    = "ReadWafLogs"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]

    resources = [
      aws_s3_bucket.waf_logs.arn,
      "${aws_s3_bucket.waf_logs.arn}/*"
    ]
  }
}

resource "aws_iam_policy" "wazuh_waf_read" {
  name        = "${var.project_name}-wazuh-waf-read"
  description = "Allow Wazuh Manager EC2 to read WAF logs from S3"
  policy      = data.aws_iam_policy_document.wazuh_waf_read.json

  tags = {
    Name = "${var.project_name}-wazuh-waf-read"
  }
}

resource "aws_iam_role_policy_attachment" "wazuh_waf_read" {
  role       = local.wazuh_role                  # ← 수정: remote_state에서 가져온 Role 이름
  policy_arn = aws_iam_policy.wazuh_waf_read.arn # ← 수정: .arn 추가
}