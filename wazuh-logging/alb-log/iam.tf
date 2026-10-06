# =======================================================
# Read ALB Logs from S3 Bucket for Wazuh (권한정책)
# =======================================================
data "aws_iam_policy_document" "alb_logs_wazuh" {
  statement {
    sid       = "ListALBLogBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.alb_logs.arn]
    condition {
      test     = "ArnEquals"
      variable = "ec2:SourceInstanceARN"
      values = [
        local.wazuh_ec2_arn
      ]
    }
  }
  statement {
    sid     = "ReadALBLogObjects"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = [
      "${aws_s3_bucket.alb_logs.arn}/${local.alb_log_object_prefix}*"
    ]
    condition {
      test     = "ArnEquals"
      variable = "ec2:SourceInstanceARN"
      values = [
        local.wazuh_ec2_arn
      ]
    }
  }
}

resource "aws_iam_policy" "alb_logs_wazuh" {
  name        = "${var.project_name}-alb-logs-wazuh-read"
  description = "Read ALB Logs from S3 Bucket for Wazuh"
  policy      = data.aws_iam_policy_document.alb_logs_wazuh.json

  tags = {
    Name      = "${var.project_name}-alb-logs-wazuh-read"
    ManagedBy = "Terraform"
  }
}

resource "aws_iam_role_policy_attachment" "alb_logs_wazuh" {
  role       = local.wazuh_role
  policy_arn = aws_iam_policy.alb_logs_wazuh.arn
}